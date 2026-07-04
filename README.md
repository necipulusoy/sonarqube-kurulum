# SonarQube Enterprise — Air-Gap Kurulum Kılavuzu

Bu paket RHEL 9 üzerinde Docker Compose V2 ile çalışan tek node SonarQube kurulumu içindir. Veritabanı container içinde kurulmaz; müşteri tarafından sağlanan external Microsoft SQL Server kullanılır. SonarQube image'ı internetteki Docker Hub yerine müşteri Nexus registry'sinden çekilir.

AWS EC2 üzerinde müşteri kurulumundan önce prova yapmak için [EC2 test kılavuzunu](docs/EC2-TEST.md) kullanın.

## Bu kılavuz nasıl kullanılmalı?

Bu dosya gerçek müşteri/production kurulumu içindir. AWS üzerinde deneme yapıyorsanız buradaki production adımlarını doğrudan uygulamak yerine EC2 kılavuzunu takip edin.

Komutlardaki `<...>` biçimindeki değerler örnektir ve çalıştırılmadan önce değiştirilmelidir. Örneğin `<REPO_URL>` yerine gerçek Git adresi yazılır. Komut bloğunun üstünde hangi makinede çalıştırılacağı belirtilmiştir; yanlış makinede çalıştırmayın.

Kurulumda dört rol vardır:

| Rol/makine | Görevi |
|---|---|
| Kendi bilgisayarınız | Kaynak kodu Git'e ilk kez push eder |
| İnternet erişimli RHEL 9 hazırlama makinesi | Offline Docker RPM paketlerini indirir |
| Müşteri Nexus yöneticisi | SonarQube Enterprise image'ını Nexus'a yükler |
| Air-gap SonarQube sunucusu | Docker'ı offline kurar ve SonarQube'u çalıştırır |
| Müşteri DBA | External MSSQL database, kullanıcı, TLS ve DB yedeğini yönetir |

Başlamadan önce şu sırayı takip edeceğinizi bilin:

```text
Repo push
  → offline RPM bundle üretimi
  → bundle'ın repoya/teslimat arşivine eklenmesi
  → SonarQube image'ının Nexus'a yüklenmesi
  → MSSQL'in DBA tarafından hazırlanması
  → air-gap hostta offline Docker kurulumu
  → .env yapılandırması
  → sistem ayarı
  → deploy
  → ilk giriş ve Enterprise lisans aktivasyonu
```

## 1. Mimari

```text
Kullanıcı / Reverse Proxy
          |
          v
SonarQube container (RHEL 9)
          |
          v
    External MSSQL

Container image kaynağı: Müşteri Nexus registry
```

Compose yalnızca SonarQube servisini çalıştırır. MSSQL kurulumu, işletimi ve yedeklemesi müşteri DBA ekibinin sorumluluğundadır.

## 2. Müşteriden Alınacak Bilgiler

Kuruluma başlamadan önce aşağıdaki tablo eksiksiz doldurulmalıdır.

| Konu | Gerekli bilgi |
|---|---|
| Nexus | Registry FQDN ve port |
| Nexus | Docker hosted/group repository adı |
| Nexus | SonarQube image tam adı, tag ve tercihen SHA-256 digest |
| Nexus | Kullanıcı adı ve parola/token yöntemi |
| Nexus | Özel CA kullanılıyorsa root/intermediate CA dosyaları |
| MSSQL | Host, port ve database adı |
| MSSQL | SonarQube kullanıcı adı ve parola |
| MSSQL | Sunucu sertifikasındaki hostname ve kurum CA zinciri |
| MSSQL | DB collation ve `READ_COMMITTED_SNAPSHOT` doğrulaması |
| Ağ | Sunucudan Nexus ve MSSQL'e açılacak portlar |
| Sunucu | CPU, RAM, disk, hostname ve erişim IP'si |
| Operasyon | DB backup/restore sahibi ve geri dönüş prosedürü |

## 3. Sunucu Gereksinimleri

- RHEL 9
- Önerilen 8 vCPU, 16 GB RAM, 200 GB SSD
- Docker Engine 24 veya üzeri
- Docker Compose V2 (`docker compose`)
- `curl`, `tar`, `firewalld` ve standart RHEL araçları
- `vm.max_map_count >= 524288`
- `fs.file-max >= 131072`

Air-gap sunucuda scriptler internetten Docker, Compose veya başka bir binary indirmez. Docker henüz kurulu değilse aşağıdaki offline RPM bundle akışı kullanılmalıdır.

### Offline Docker paketini hazırlama ve repoya ekleme

Akış üç makine/ortam üzerinden ilerler:

1. Bu kaynak repo Git sunucusuna push edilir.
2. İnternet erişimli RHEL 9 x86_64 makine repoyu clone eder ve offline RPM bundle'ını üretir.
3. RPM'lerle güncellenmiş repo air-gap RHEL 9 sunucuya aktarılır.

#### A. İlk kaynak kod push'u

Kendi bilgisayarınızda:

```bash
git add .
git commit -m "SonarQube air-gap kurulum paketi"
git push
```

Bu aşamada `packages/` dizininin henüz bulunmaması normaldir.

#### B. İnternet erişimli RHEL 9 makinede paketleri üretme

İnternet erişimli RHEL 9 x86_64 makinede:

```bash
git clone <REPO_URL> sonarqube-kurulum
cd sonarqube-kurulum
sudo bash scripts/00-prepare-offline-packages.sh
```

Script her zaman clone edilen reponun kök dizini altında aşağıdaki yapıyı oluşturur; başka bir dizine elle taşımanız gerekmez:

```text
sonarqube-kurulum/
└── packages/
    ├── BUNDLE-INFO.txt
    ├── SHA256SUMS
    ├── docker-rhel-gpg
    └── rhel9-x86_64/
        ├── containerd.io-....rpm
        ├── docker-ce-....rpm
        ├── docker-ce-cli-....rpm
        ├── docker-buildx-plugin-....rpm
        ├── docker-compose-plugin-....rpm
        └── diğer-bağımlılıklar.rpm
```

Dosyaları kontrol edin:

```bash
ls -lh packages/rhel9-x86_64/
(cd packages && sha256sum --check SHA256SUMS)
git status --short
```

Sonra oluşan `packages/` dizinini aynı repoya ekleyip geri push edin:

```bash
git add packages/
git commit -m "RHEL 9 x86_64 offline Docker RPM bundle"
git push
```

`packages/` bilerek `.gitignore` kapsamına alınmamıştır. Git sunucusunun toplam repo veya tek dosya boyutu politikası RPM'leri kabul etmiyorsa bu commit yapılmamalı; aşağıdaki arşiv yöntemi kullanılmalıdır. Paketlerin içinde parola, token veya lisans anahtarı bulunmaz.

#### C. Air-gap sunucuya aktarma

Air-gap ortam kurum içi Git sunucusuna erişebiliyorsa, güncellenmiş repoyu doğrudan clone edin:

```bash
git clone <KURUM_ICI_REPO_URL> sonarqube-kurulum
cd sonarqube-kurulum
test -f packages/SHA256SUMS
```

Air-gap ortam hiçbir Git sunucusuna erişemiyorsa internet erişimli RHEL makinede reponun bir üst dizininden teslimat arşivi oluşturun:

```bash
tar --exclude='sonarqube-kurulum/.git' \
  -czf sonarqube-kurulum-offline.tar.gz sonarqube-kurulum/
sha256sum sonarqube-kurulum-offline.tar.gz \
  > sonarqube-kurulum-offline.tar.gz.sha256
```

İki dosyayı onaylı USB/SFTP/artifact transfer yöntemiyle air-gap sunucuya taşıyın. Air-gap sunucuda:

```bash
sha256sum --check sonarqube-kurulum-offline.tar.gz.sha256
tar xzf sonarqube-kurulum-offline.tar.gz
cd sonarqube-kurulum
```

#### D. Air-gap RHEL sunucuda Docker kurulumu

```bash
sudo bash scripts/01-install-offline-docker.sh
```

Installer mevcut kullanıcıyı `docker` grubuna ekler. Komut tamamlanınca SSH oturumunu kapatıp yeniden bağlanın; aksi hâlde `permission denied while trying to connect to the Docker daemon socket` hatası alabilirsiniz. Yeniden bağlandıktan sonra repo dizinine dönüp kontrolü çalıştırın:

```bash
cd sonarqube-kurulum
bash scripts/02-prerequisites.sh
```

Başarılı sonuçta Docker ve Compose sürümleri ekrana yazılır. Hata varsa sonraki adıma geçmeyin.

Kurulum scripti önce `packages/SHA256SUMS` ile bütünlük doğrulaması yapar, ardından yalnızca `packages/rhel9-x86_64/` içindeki RPM'leri `--disablerepo='*'` ile kurar. İnternete veya harici paket repository'sine gitmez.

## 4. Image'ın Nexus'a Hazırlanması

Bu işlem internet erişimi olan aktarım ortamında veya müşteri image transfer prosedürüyle yapılır. Kullanılacak SonarQube Enterprise sürümü müşteri lisansı ve upgrade politikasıyla doğrulanmalıdır.

Örnek akış:

```bash
docker pull sonarqube:<ONAYLI_SURUM>-enterprise
docker tag sonarqube:<ONAYLI_SURUM>-enterprise \
  nexus.example.local:5000/docker-hosted/sonarqube:<ONAYLI_SURUM>-enterprise
docker login nexus.example.local:5000
docker push nexus.example.local:5000/docker-hosted/sonarqube:<ONAYLI_SURUM>-enterprise
docker inspect --format='{{index .RepoDigests 0}}' \
  nexus.example.local:5000/docker-hosted/sonarqube:<ONAYLI_SURUM>-enterprise
```

Digest kaydedilmeli ve mümkünse `.env` içinde image digest ile sabitlenmelidir:

```ini
SONARQUBE_IMAGE=nexus.example.local:5000/docker-hosted/sonarqube@sha256:<DIGEST>
```

### Nexus özel CA sertifikası

Nexus kurum içi CA kullanıyorsa CA, Docker host tarafından güvenilir olmalıdır. RHEL trust store ve Docker daemon yapılandırması müşteri güvenlik standardına göre yapılmalı, ardından Docker yeniden başlatılmalıdır. `insecure-registries` kullanılması önerilmez.

Müşteriden alınan CA dosyasının adı `nexus-ca.crt`, registry adresinin `nexus.example.local:5000` olduğu örnek:

```bash
sudo cp nexus-ca.crt /etc/pki/ca-trust/source/anchors/nexus-ca.crt
sudo update-ca-trust

sudo mkdir -p /etc/docker/certs.d/nexus.example.local:5000
sudo cp nexus-ca.crt \
  /etc/docker/certs.d/nexus.example.local:5000/ca.crt

sudo systemctl restart docker
```

Registry hostname ve portu gerçek Nexus adresiyle birebir aynı yazılmalıdır. Root ve intermediate CA ayrı dosyalardaysa müşteri PKI ekibinin verdiği doğru zinciri kullanın.

Doğrulama:

```bash
docker login nexus.example.local:5000
docker pull nexus.example.local:5000/docker-hosted/sonarqube:<ONAYLI_SURUM>-enterprise
```

Nexus parolası `.env`, Compose veya script içine yazılmamalıdır.

Beklenen sonuç: `docker pull` komutu `Downloaded newer image` veya `Image is up to date` benzeri başarılı bir mesajla bitmelidir. `x509: certificate signed by unknown authority` görülürse Nexus CA güveni henüz doğru kurulmamıştır.

## 5. External MSSQL Hazırlığı

DBA aşağıdaki gereksinimleri sağlamalıdır:

```sql
CREATE DATABASE [sonarqube]
    COLLATE SQL_Latin1_General_CP1_CS_AS;
GO

ALTER DATABASE [sonarqube]
    SET READ_COMMITTED_SNAPSHOT ON;
GO

CREATE LOGIN sonarqube WITH PASSWORD = '<GUCLU_PAROLA>';
GO

USE [sonarqube];
GO
CREATE USER sonarqube FOR LOGIN sonarqube;
GO
ALTER ROLE db_owner ADD MEMBER sonarqube;
GO
```

Doğrulama:

```sql
SELECT name, collation_name, is_read_committed_snapshot_on
FROM sys.databases
WHERE name = 'sonarqube';
```

Beklenen doğrulama sonucu:

- `collation_name` değeri `SQL_Latin1_General_CP1_CS_AS` olmalıdır.
- `is_read_committed_snapshot_on` değeri `1` olmalıdır.
- SonarQube DB kullanıcısı database'e bağlanabilmelidir.

Production JDBC bağlantısında TLS kullanılmalıdır. Örnek:

```ini
SONAR_JDBC_URL=jdbc:sqlserver://mssql.example.local:1433;databaseName=sonarqube;encrypt=true;trustServerCertificate=false;hostNameInCertificate=mssql.example.local
```

`trustServerCertificate=true` veya `encrypt=false` yalnızca müşteri güvenlik ekibinin açık kabulüyle kullanılmalıdır. MSSQL CA zinciri SonarQube JVM trust store'unda güvenilir değilse ayrıca truststore hazırlanıp container'a read-only mount edilmelidir.

## 6. Yapılandırma

Örnek dosyayı kopyalayın:

```bash
cp .env.example .env
chmod 600 .env
vi .env
```

Örnek `.env` dosyasında `example.local`, `DEGISTIRIN` veya örnek Nexus adresi bırakılmamalıdır. Kontrol edin:

```bash
grep -nE 'example\.local|DEGISTIRIN|<|>' .env
```

Komut çıktı veriyorsa kalan örnek değerleri düzeltmeden deploy etmeyin.

En az şu alanları gerçek değerlerle değiştirin:

- `SONARQUBE_IMAGE`
- `SONAR_JDBC_URL`, `SONAR_JDBC_USERNAME`, `SONAR_JDBC_PASSWORD`

`.env` shell scripti değildir ve hiçbir script tarafından `source` edilmez. Parolalar özel karakterlerin Compose tarafından yorumlanmaması için örnekteki gibi tek tırnakla yazılmalıdır. Dosya Git'e dahil edilmez.

Reverse proxy aynı host üzerinde çalışacaksa:

```ini
SONAR_BIND_ADDRESS=127.0.0.1
SONAR_HOST_PORT=9000
```

Doğrudan ağdan erişilecekse `SONAR_BIND_ADDRESS=0.0.0.0` kullanılabilir; firewall kaynak IP/subnet ile sınırlandırılmalıdır.

## 7. Sistem Yapılandırması

```bash
sudo bash scripts/03-configure-system.sh
```

Script kernel limitlerini ve ulimit değerlerini ayarlar; `.env` dosyasını çalıştırmadan JDBC host/port erişimini kontrol eder. Güvenlik nedeniyle firewall portunu global olarak açmaz. Kaynak subnet'e özel firewall kuralı müşteri ağ ekibi tarafından uygulanmalıdır.

Air-gap ağ kuralları en az şu çıkışları sağlamalıdır:

- RHEL host → Nexus registry portu
- SonarQube container → MSSQL TCP/1433 veya müşteri portu
- Yönetim ağı → SonarQube TCP/9000 veya reverse proxy TCP/443

Script sonunda DB portu için `erişilebilir` mesajı beklenir. `ulaşılamıyor` uyarısı görülürse MSSQL host/port, DNS, route, host firewall ve müşteri ağ kuralı kontrol edilmelidir; deploy'a geçmeyin.

## 8. Deploy

Önce Compose çıktısını ve Nexus erişimini doğrulayın:

```bash
docker compose config
docker compose pull
```

`docker compose config` gizli değerleri ekrana yazabileceği için çıktısını ticket, e-posta veya ortak log alanına kopyalamayın. Komut hata vermeden tamamlanmalı ve yalnızca `sonarqube` servisini göstermelidir:

```bash
docker compose config --services
# Beklenen çıktı: sonarqube
```

Kurulum:

```bash
sudo bash scripts/04-deploy.sh
```

Script SonarQube hazır olduğunda başarıyla çıkar. Beş dakikalık zaman aşımı veya başka bir hata durumunda non-zero exit code döndürür.

Manuel takip:

```bash
docker compose ps
docker compose logs -f sonarqube
curl -fsS http://127.0.0.1:9000/api/system/status
```

İlk giriş bilgileri `admin / admin` değeridir. İlk girişte parola hemen değiştirilmelidir.

Tarayıcı erişemiyorsa önce sunucu üzerinde kontrol edin:

```bash
curl -fsS http://127.0.0.1:9000/api/system/status
```

Bu komut çalışıyor fakat kullanıcı bilgisayarından erişilemiyorsa sorun SonarQube değil; firewall, Security Group, reverse proxy veya ağ yönlendirmesidir.

## 9. Enterprise Lisans Aktivasyonu

Lisans aktivasyonu script tarafından yapılmaz. SonarQube external MSSQL ile başarıyla başladıktan ve admin parolası değiştirildikten sonra:

1. `Administration → System` ekranından Server ID bilgisini alın.
2. Server ID'yi internet erişimli ve onaylı kanal üzerinden SonarSource veya lisans sağlayıcısına iletin.
3. Alınan offline/server-ID tabanlı Enterprise lisans anahtarını `Administration → Configuration → License Manager` ekranından girin.
4. Edition, lisans süresi ve LOC limitini aynı ekrandan doğrulayın.

Server ID external DB kimliğine bağlıdır. DB hostname/IP, database adı, boş DB ile yeniden kurulum veya desteklenmeyen DB taşıma işlemleri lisansı geçersiz kılabilir. Böyle bir değişiklikten önce lisans sağlayıcısı ve DBA ile plan yapılmalıdır. Geçici EC2 testinde production lisansı kullanılmamalıdır; gerekiyorsa evaluation, test veya staging lisansı kullanılmalıdır.

## 10. Yedekleme Sorumlulukları

SonarQube'un asıl kalıcı verisi external MSSQL veritabanıdır. Tam geri dönüş için DB backup ve restore prosedürü DBA tarafından hazırlanmalı ve test edilmelidir.

Bu paketteki script DB yedeği almaz. Yalnızca eklenti volume'unu arşivler:

```bash
sudo BACKUP_DIR=/guvenli/yedek/sonarqube bash scripts/05-backup.sh
```

Script ek bir public container image çekmez. `sonarqube_data` Elasticsearch indeksidir; DB'den yeniden üretilebilir ve temel backup kaynağı olarak kabul edilmez. DB yedeği olmadan uygulama dosyası yedeği tek başına yeterli değildir.

## 11. Operasyon Komutları

```bash
docker compose ps
docker compose logs --tail=200 sonarqube
docker compose restart sonarqube
docker compose down
docker compose up -d
```

`docker compose down -v` volume'ları siler ve normal operasyonda kullanılmamalıdır.

## 12. Sık Karşılaşılan Hatalar

### Docker socket permission denied

Belirti: `permission denied while trying to connect to the Docker daemon socket`.

Çözüm: Offline installer sonrasında SSH oturumunu kapatıp yeniden bağlanın. Ardından `id` çıktısında `docker` grubunun bulunduğunu doğrulayın.

### Nexus sertifika hatası

Belirti: `x509: certificate signed by unknown authority`.

Çözüm: Nexus root/intermediate CA zincirini RHEL ve Docker güven deposuna müşteri standardına göre ekleyin, Docker'ı yeniden başlatın ve `docker login/pull` testini tekrarlayın. `insecure-registries` ile geçici çözüm üretmeyin.

### MSSQL bağlantı hatası

Belirti: loglarda `Login failed`, `Cannot open database` veya bağlantı zaman aşımı.

Kontrol sırası: host/port erişimi, kullanıcı/parola, database adı, TLS sertifika güveni, collation ve `READ_COMMITTED_SNAPSHOT`.

```bash
docker compose logs --tail=200 sonarqube
```

### Elasticsearch başlangıç hatası

Belirti: `bootstrap check failure` veya container'ın sürekli restart olması.

```bash
sysctl vm.max_map_count
docker compose logs --tail=200 sonarqube
```

`vm.max_map_count` en az `524288` olmalıdır. `scripts/03-configure-system.sh` tekrar çalıştırılabilir.

### Deploy beş dakikada tamamlanmıyor

İlk DB migration uzun sürebilir. Script hata verdikten sonra container'ı silmeyin; önce logları inceleyin:

```bash
docker compose ps
docker compose logs -f sonarqube
```

Loglar ilerliyorsa bekleyip API durumunu tekrar kontrol edin. Tekrarlayan hata varsa kök neden çözülmeden restart döngüsü oluşturmayın.

## 13. Production Kontrol Listesi

- [ ] SonarQube sürümü ve Enterprise lisansı doğrulandı
- [ ] Server ID kaydedildi ve doğru Enterprise lisansı aktive edildi
- [ ] Nexus image tag/digest bilgisi kaydedildi
- [ ] Nexus özel CA güveni doğrulandı
- [ ] `docker compose pull` yalnızca Nexus'a erişerek başarılı oldu
- [ ] MSSQL TLS bağlantısı başarılı
- [ ] MSSQL collation doğru
- [ ] `READ_COMMITTED_SNAPSHOT ON`
- [ ] DBA backup ve restore testi tamamlandı
- [ ] `.env` izinleri `600`
- [ ] Admin varsayılan parolası değiştirildi
- [ ] 9000 portuna erişim sınırlandırıldı veya reverse proxy kullanıldı
- [ ] Monitoring `/api/system/health` üzerinden yapılandırıldı
- [ ] Log ve disk kullanım alarmları tanımlandı
- [ ] Restore ve felaket kurtarma prosedürü dokümante edildi
