IF DB_ID(N'sonarqube_test') IS NULL
BEGIN
    CREATE DATABASE [sonarqube_test]
        COLLATE SQL_Latin1_General_CP1_CS_AS;
END;
GO

ALTER DATABASE [sonarqube_test]
    SET READ_COMMITTED_SNAPSHOT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'sonarqube_test')
BEGIN
    CREATE LOGIN [sonarqube_test]
        WITH PASSWORD = '$(SONAR_PASSWORD)', CHECK_POLICY = ON;
END;
GO

USE [sonarqube_test];
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sonarqube_test')
BEGIN
    CREATE USER [sonarqube_test] FOR LOGIN [sonarqube_test];
END;
GO

IF IS_ROLEMEMBER(N'db_owner', N'sonarqube_test') <> 1
BEGIN
    ALTER ROLE [db_owner] ADD MEMBER [sonarqube_test];
END;
GO

SELECT name, collation_name, is_read_committed_snapshot_on
FROM sys.databases
WHERE name = N'sonarqube_test';
GO
