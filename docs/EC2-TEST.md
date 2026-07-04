# AWS EC2 Üzerinde SonarQube Enterprise Kurulum Provası

Bu kılavuz AWS ve SonarQube konusunda başlangıç seviyesinde olan bir kullanıcının iki ayrı EC2 kullanarak kurulumu baştan sona deneyebilmesi için hazırlanmıştır.

Bu ortam production değildir. Amaç şunları doğrulamaktır:

- RHEL 9 için offline Docker RPM bundle'ı hazırlanabiliyor mu?
- Docker ve Compose V2 bu bundle ile kurulabiliyor mu?
- SonarQube Enterprise image'ı çalışıyor mu?
- SonarQube ayrı bir sunucudaki MSSQL'e bağlanabiliyor mu?
- Database migration, restart, health check ve temel backup başarılı mı?

## 1. Kurulacak mimari

İki EC2 oluşturulacaktır. MSSQL'i SonarQube ile aynı EC2 üzerinde çalıştırmayın; aksi hâlde müşterideki external DB bağlantısını doğru simüle etmiş olmazsınız.

```text
Kendi bilgisayarınız
       |
       | TCP/9000 (yalnızca sizin IP'niz)
       v
SonarQube EC2 ───── TCP/1433 ─────> MSSQL EC2
 RHEL 9                              RHEL 9
 Docker                              Docker
 SonarQube Enterprise                SQL Server 2022 Developer
```

Komut bloklarında hangi makinede çalışılacağı `[SONARQUBE EC2]` veya `[MSSQL EC2]` şeklinde belirtilir. `<...>` içindeki değerleri gerçek değerlerle değiştirin.

## 2. Tahmini AWS kaynakları

| Kaynak | Önerilen test değeri |
|--------|---|
| Region | Size yakın herhangi bir AWS region |
| VPC | İki EC2 için aynı VPC |
| AMI | Red Hat Enterprise Linux 9, x86_64 |
| SonarQube EC2 | `m6i.2xlarge`, 8 vCPU / 32 GiB |
| MSSQL EC2 | `m6i.large`, 2 vCPU / 8 GiB |
| SonarQube disk | 100 GiB gp3 |
| MSSQL disk | 50 GiB gp3 |
| Yönetim | Tercihen AWS Systems Manager Session Manager; alternatif SSH |

Gerçek hedefteki 8 vCPU / 16 GiB sınırını ayrıca denemek için sonraki testte `c6i.2xlarge` kullanılabilir. İlk fonksiyonel testte 32 GiB RAM, uygulama hatasıyla bellek yetersizliğini birbirinden ayırmayı kolaylaştırır.

Her iki EC2 de bu prova sırasında Red Hat repository, Docker repository ve container registry'lere HTTPS/443 üzerinden çıkabilmelidir.

## 3. Security Group oluşturma

AWS Console'da EC2 → Security Groups bölümünden aynı VPC içinde iki Security Group oluşturun.

### `sonarqube-test-sg`

Inbound kuralları:

| Protokol/port | Kaynak | Amaç |
|---|---|---|
| TCP/9000 | Sadece kendi public IP'niz `/32` | SonarQube web arayüzü |
| TCP/22 | Sadece kendi public IP'niz `/32` | Yalnızca SSH kullanacaksanız |

### `mssql-test-sg`

Inbound kuralları:

| Protokol/port | Kaynak | Amaç |
|---|---|---|
| TCP/1433 | `sonarqube-test-sg` | Yalnızca SonarQube EC2'nin DB'ye erişmesi |
| TCP/22 | Sadece kendi public IP'niz `/32` | Yalnızca SSH kullanacaksanız |

TCP/9000 veya TCP/1433 için kaynak olarak `0.0.0.0/0` kullanmayın. İki EC2 aynı VPC içinde private IP adresleriyle haberleşmelidir.

## 4. EC2 makinelerini oluşturma

AWS Console → EC2 → Launch instance üzerinden iki makine oluşturun.

### SonarQube EC2

- Name: `sonarqube-test`
- AMI: RHEL 9 x86_64
- Instance type: `m6i.2xlarge`
- Disk: 100 GiB gp3
- Security Group: `sonarqube-test-sg`

### MSSQL EC2

- Name: `mssql-test`
- AMI: RHEL 9 x86_64
- Instance type: `m6i.large`
- Disk: 50 GiB gp3
- Security Group: `mssql-test-sg`

Her iki instance `Running` durumuna geldikten sonra şu bilgileri not edin:

- SonarQube EC2 public IP veya Session Manager erişimi
- SonarQube EC2 private IP
- MSSQL EC2 private IP

MSSQL JDBC bağlantısında MSSQL EC2 private IP kullanılacaktır.

## 5. Repoyu iki EC2'ye indirme

Önce MSSQL EC2'ye bağlanın.

```bash
# [MSSQL EC2]
sudo dnf install -y git
git clone <REPO_URL> sonarqube-kurulum
cd sonarqube-kurulum
```

Aynı işlemi SonarQube EC2'de yapın:

```bash
# [SONARQUBE EC2]
sudo dnf install -y git
git clone <REPO_URL> sonarqube-kurulum
cd sonarqube-kurulum
```

`git clone` kimlik doğrulaması gerekiyorsa kurumunuzun personal access token veya SSH key yöntemini kullanın. Token'ı repo dosyalarına yazmayın.

## 6. Docker'ı iki EC2'ye kurma

EC2 testi internet erişimli olduğu için her iki makinede önce RPM bundle'ını üretip ardından aynı bundle ile offline kurulum yapacağız. Böylece müşteri ortamında kullanılacak gerçek akış da test edilmiş olur.

MSSQL EC2 üzerinde:

```bash
# [MSSQL EC2] repo kök dizininde
sudo bash scripts/00-prepare-offline-packages.sh
sudo bash scripts/01-install-offline-docker.sh
```

SonarQube EC2 üzerinde:

```bash
# [SONARQUBE EC2] repo kök dizininde
sudo bash scripts/00-prepare-offline-packages.sh
sudo bash scripts/01-install-offline-docker.sh
```

Installer kullanıcıyı `docker` grubuna ekler. Her iki makinedeki SSH/Session Manager oturumunu kapatıp yeniden bağlanın. Bu adım atlanırsa Docker socket yetki hatası alınabilir.

Yeniden bağlandıktan sonra iki makinede de kontrol edin:

```bash
cd sonarqube-kurulum
bash scripts/02-prerequisites.sh
```

Beklenen sonuç:

- Docker sürümü yazılır.
- Docker Compose V2 sürümü yazılır.
- `Docker daemon çalışmıyor` veya permission hatası görülmez.

## 7. MSSQL test sunucusunu hazırlama

Bu bölüm yalnızca MSSQL EC2 üzerinde uygulanır.

Ortam dosyasını oluşturun:

```bash
# [MSSQL EC2]
cd sonarqube-kurulum
cp test/mssql/.env.example test/mssql/.env
chmod 600 test/mssql/.env
vi test/mssql/.env
```

Dosyada iki parolayı değiştirin:

```ini
MSSQL_SA_PASSWORD='Guclu-Bir-SA-Parolasi_2026!'
SONAR_DB_PASSWORD='Guclu-Bir-Sonar-Parolasi_2026!'
```

Kurallar:

- En az sekiz karakter kullanın.
- Büyük harf, küçük harf, rakam ve sembol içersin.
- Bu test akışında parolada tek tırnak (`'`) kullanmayın.
- Parolaları Git'e commit etmeyin.
- `SONAR_DB_PASSWORD` değerini daha sonra SonarQube EC2 `.env` dosyasında aynen kullanacaksınız.

Örnek değerlerin kalmadığını kontrol edin:

```bash
grep -n 'ChangeThis-' test/mssql/.env
```

Komut çıktı veriyorsa parolalar hâlâ değiştirilmemiştir.

SQL Server'ı başlatın ve database'i oluşturun:

```bash
# [MSSQL EC2]
sudo bash scripts/10-ec2-start-test-mssql.sh
```

Script şu işlemleri yapar:

1. `mcr.microsoft.com/mssql/server:2022-latest` image'ını çeker.
2. SQL Server 2022 Developer container'ını başlatır.
3. `sonarqube_test` database'ini oluşturur.
4. Collation değerini `SQL_Latin1_General_CP1_CS_AS` yapar.
5. `READ_COMMITTED_SNAPSHOT` özelliğini açar.
6. `sonarqube_test` login/user oluşturur ve `db_owner` rolüne ekler.
7. SonarQube kullanıcısıyla bağlantıyı doğrular.

Bu image `MSSQL_PID=Developer` ile yalnızca development/test amaçlı kullanılır. Production için kullanmayın. Scripti çalıştırmak Microsoft SQL Server container EULA şartlarını kabul etmek anlamına gelir.

Container durumunu kontrol edin:

```bash
# [MSSQL EC2]
docker compose \
  --env-file test/mssql/.env \
  -f test/mssql/docker-compose.yml ps
```

Beklenen durum `Up` ve `healthy` olmalıdır. Hata varsa:

```bash
docker compose \
  --env-file test/mssql/.env \
  -f test/mssql/docker-compose.yml logs --tail=200 mssql
```

MSSQL EC2 private IP adresini alın ve not edin:

```bash
hostname -I | awk '{print $1}'
```

## 8. SonarQube test ayarlarını hazırlama

Bu bölüm yalnızca SonarQube EC2 üzerinde uygulanır.

Örnek dosyayı kopyalayın:

```bash
# [SONARQUBE EC2]
cd sonarqube-kurulum
cp .env.ec2.example .env
chmod 600 .env
vi .env
```

En az şu üç değeri değiştirin:

```ini
SONARQUBE_IMAGE=sonarqube:<ONAYLI_SURUM>-enterprise
SONAR_JDBC_URL=jdbc:sqlserver://<MSSQL_PRIVATE_IP>:1433;databaseName=sonarqube_test;encrypt=true;trustServerCertificate=true
SONAR_JDBC_PASSWORD='<MSSQL_EC2_ENV_DOSYASINDAKI_SONAR_DB_PASSWORD>'
```

- `<ONAYLI_SURUM>` yerine test edeceğiniz gerçek Enterprise tag'ini yazın.
- `<MSSQL_PRIVATE_IP>` yerine önceki bölümde kaydettiğiniz private IP'yi yazın.
- DB parolası MSSQL EC2 `test/mssql/.env` içindeki `SONAR_DB_PASSWORD` ile birebir aynı olmalıdır.
- `SONAR_JDBC_USERNAME=sonarqube_test` ve database adı `sonarqube_test` olarak kalmalıdır.

Test SQL Server container'ı self-signed sertifika kullandığı için yalnızca bu EC2 testinde `trustServerCertificate=true` kullanılır. Gerçek müşteri `.env.example` dosyası `trustServerCertificate=false` kullanır; production güvenliği düşürülmemelidir.

Örnek değer kalmadığını kontrol edin:

```bash
grep -nE '<|>|ONAYLI|DEGISTIRIN' .env
```

Komut çıktı veriyorsa dosyayı düzeltmeden devam etmeyin.

## 9. SonarQube EC2'den MSSQL erişimini test etme

```bash
# [SONARQUBE EC2]
timeout 5 bash -c 'echo >/dev/tcp/<MSSQL_PRIVATE_IP>/1433' \
  && echo 'MSSQL portu erişilebilir' \
  || echo 'MSSQL portuna erişilemiyor'
```

Erişilemiyorsa aşağıdakileri kontrol edin:

1. MSSQL container `healthy` mi?
2. Doğru MSSQL private IP kullanıldı mı?
3. İki EC2 aynı VPC'de mi?
4. `mssql-test-sg` TCP/1433 kaynağı `sonarqube-test-sg` olarak tanımlı mı?
5. RHEL host firewall trafiği engelliyor mu?

Port erişimi başarılı olmadan SonarQube deploy adımına geçmeyin.

## 10. SonarQube sistem ayarlarını uygulama

```bash
# [SONARQUBE EC2]
cd sonarqube-kurulum
sudo bash scripts/03-configure-system.sh
```

Beklenen değerler:

```text
vm.max_map_count : 524288
fs.file-max      : 131072 veya daha yüksek
MSSQL portu erişilebilir
```

DB portu için uyarı görülürse önce ağ problemini çözün.

## 11. Compose yapılandırmasını doğrulama

```bash
# [SONARQUBE EC2]
docker compose config --services
```

Beklenen tek çıktı:

```text
sonarqube
```

Sonra image'ı çekin:

```bash
docker compose pull
```

Docker Hub rate limit veya image tag bulunamadı hatası alınırsa `SONARQUBE_IMAGE` değerini kontrol edin. Müşteri provasında Docker Hub yerine Nexus image adresi kullanılmalıdır.

`docker compose config` komutunun tam çıktısı parolayı gösterebilir; çıktıyı ticket veya ortak log alanına yüklemeyin.

## 12. SonarQube'u başlatma

```bash
# [SONARQUBE EC2]
sudo bash scripts/04-deploy.sh
```

Script en fazla beş dakika bekler. Başarılı olduğunda SonarQube'un hazır olduğunu ve erişim adresini yazar. İlk database migration nedeniyle başlangıç birkaç dakika sürebilir.

Script hata verirse hemen container/volume silmeyin. Önce logları okuyun:

```bash
docker compose ps
docker compose logs --tail=200 sonarqube
```

## 13. Otomatik smoke test

```bash
# [SONARQUBE EC2]
bash scripts/90-ec2-smoke-test.sh
```

Başarılı sonuçta şunlar yazılır:

```text
SonarQube status: UP
Container health: healthy
EC2 smoke test başarılı.
```

## 14. Web arayüzüne giriş

Tarayıcıdan aşağıdaki adresi açın:

```text
http://<SONARQUBE_EC2_PUBLIC_IP>:9000
```

İlk giriş:

```text
Kullanıcı: admin
Parola: admin
```

SonarQube ilk girişte admin parolasını değiştirmenizi ister. Test parolasını dahi Git'e veya dokümana yazmayın.

Tarayıcı erişemiyor fakat aşağıdaki komut başarılıysa sorun uygulamada değil, Security Group/ağ tarafındadır:

```bash
# [SONARQUBE EC2]
curl -fsS http://127.0.0.1:9000/api/system/status
```

## 15. Enterprise lisansı hakkında

Geçici EC2 testinde production lisansını kullanmayın. Enterprise özelliklerini doğrulamak gerekiyorsa evaluation, test veya sözleşmede varsa staging lisansı kullanın.

Lisans aktivasyonu gerekiyorsa:

1. `Administration → System` ekranından Server ID alın.
2. Test/evaluation lisansını temin edin.
3. `Administration → Configuration → License Manager` ekranından lisansı girin.

Server ID test database'ine bağlıdır. Geçici DB silindiğinde bu test Server ID'si production için kullanılmamalıdır.

## 16. Restart ve kalıcılık testi

```bash
# [SONARQUBE EC2]
docker compose restart sonarqube
```

Bir süre bekleyip smoke testi tekrar çalıştırın:

```bash
bash scripts/90-ec2-smoke-test.sh
```

Bu test database ve Docker volume verilerinin restart sonrasında korunduğunu doğrular.

## 17. Backup scriptini test etme

```bash
# [SONARQUBE EC2]
sudo BACKUP_DIR=/tmp/sonarqube-backup-test \
  bash scripts/05-backup.sh
ls -lh /tmp/sonarqube-backup-test
```

Bir `sonarqube_extensions_*.tar.gz` dosyası oluşmalıdır. Bu script MSSQL yedeği almaz. Production DB backup/restore işlemi DBA sorumluluğundadır.

## 18. Test kabul kriterleri

Test aşağıdaki maddelerin tamamı sağlanınca başarılı kabul edilir:

- [ ] İki EC2 oluşturuldu ve yalnızca gerekli Security Group kuralları açıldı.
- [ ] Offline RPM bundle her iki RHEL 9 makinede üretildi/kuruldu.
- [ ] Docker ve Compose V2 doğrulandı.
- [ ] MSSQL container `healthy` oldu.
- [ ] `sonarqube_test` database ve kullanıcı oluşturuldu.
- [ ] SonarQube EC2'den MSSQL TCP/1433 erişimi başarılı.
- [ ] Compose yalnızca `sonarqube` servisini oluşturdu.
- [ ] SonarQube image beklenen tag/digest ile çalıştı.
- [ ] `/api/system/status` yanıtı `UP` oldu.
- [ ] SonarQube container `healthy` oldu.
- [ ] İlk web girişi başarılı oldu ve admin parolası değiştirildi.
- [ ] Restart sonrasında smoke test tekrar başarılı oldu.
- [ ] Backup scripti extensions arşivi üretti.
- [ ] Loglarda tekrarlayan DB, Elasticsearch veya JVM hatası yok.

## 19. Test sonuçlarını toplama

```bash
# [SONARQUBE EC2]
mkdir -p test-results
docker compose config --services > test-results/compose-services.txt
docker compose ps > test-results/compose-ps.txt
docker compose logs --no-color sonarqube > test-results/sonarqube.log
```

Tam `docker compose config` çıktısı parola içerebileceği için sonuç paketine eklenmez. Logları paylaşmadan önce hostname, IP, kullanıcı adı veya başka hassas bilgiler açısından inceleyin. `test-results/` Git tarafından yok sayılır.

## 20. Sık karşılaşılan EC2 test hataları

### Docker permission denied

Offline installer sonrası oturumu kapatıp yeniden bağlanın. `id` komutunda `docker` grubu görünmelidir.

### MSSQL container başlamıyor

En sık neden parola politikasına uymayan `MSSQL_SA_PASSWORD` değeridir.

```bash
docker compose --env-file test/mssql/.env \
  -f test/mssql/docker-compose.yml logs --tail=200 mssql
```

### SonarQube MSSQL'e bağlanamıyor

- JDBC private IP doğru mu?
- `SONAR_DB_PASSWORD` iki `.env` dosyasında aynı mı?
- Security Group kaynağı doğru mu?
- Database adı ve kullanıcı `sonarqube_test` mi?

### SonarQube container restart döngüsünde

```bash
sysctl vm.max_map_count
docker compose logs --tail=300 sonarqube
```

`vm.max_map_count` en az `524288` olmalıdır.

### Web arayüzü açılmıyor

Önce SonarQube EC2 içinde `curl http://127.0.0.1:9000/api/system/status` çalıştırın. Lokal erişim başarılıysa `sonarqube-test-sg` TCP/9000 kaynağını ve EC2 public IP'yi kontrol edin.

## 21. Test sonrası temizlik

Gerekli sonuçları aldıktan sonra maliyet oluşmaması için:

1. SonarQube EC2'yi terminate edin.
2. MSSQL EC2'yi terminate edin.
3. Instance'larla birlikte silinmeyen EBS volume/snapshot var mı kontrol edin.
4. Geçici Elastic IP varsa release edin.
5. `sonarqube-test-sg` ve `mssql-test-sg` artık kullanılmıyorsa silin.
6. Test/evaluation lisansı ve Server ID kayıtlarını production kayıtlarından ayrı tutun.

`.env`, DB parolaları, lisans anahtarı ve hassas loglar Git'e eklenmemelidir.
