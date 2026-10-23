/*
    Tablas de perfiles de acceso web (menú / opciones).
    Desplegar inicialmente en hm_lumat.
*/
IF OBJECT_ID('dbo.WEB_UserAccessProfile', 'U') IS NOT NULL
    DROP TABLE dbo.WEB_UserAccessProfile;
GO
IF OBJECT_ID('dbo.WEB_AccessProfileMenu', 'U') IS NOT NULL
    DROP TABLE dbo.WEB_AccessProfileMenu;
GO
IF OBJECT_ID('dbo.WEB_AccessProfile', 'U') IS NOT NULL
    DROP TABLE dbo.WEB_AccessProfile;
GO
IF OBJECT_ID('dbo.WEB_MenuOption', 'U') IS NOT NULL
    DROP TABLE dbo.WEB_MenuOption;
GO

CREATE TABLE dbo.WEB_MenuOption (
    MenuCode     VARCHAR(60)  NOT NULL,
    Title        VARCHAR(120) NOT NULL,
    ParentCode   VARCHAR(60)  NULL,
    SortOrder    INT          NOT NULL CONSTRAINT DF_WEB_MenuOption_Sort DEFAULT (0),
    Endpoint     VARCHAR(120) NULL,
    RoutePrefix  VARCHAR(120) NULL,
    Status       CHAR(1)      NOT NULL CONSTRAINT DF_WEB_MenuOption_Status DEFAULT ('A'),
    CONSTRAINT PK_WEB_MenuOption PRIMARY KEY (MenuCode)
);
GO

CREATE TABLE dbo.WEB_AccessProfile (
    ProfileCode  VARCHAR(30)  NOT NULL,
    Name         VARCHAR(120) NOT NULL,
    FlagAdmin    CHAR(1)      NOT NULL CONSTRAINT DF_WEB_AccessProfile_FlagAdmin DEFAULT ('N'),
    Status       CHAR(1)      NOT NULL CONSTRAINT DF_WEB_AccessProfile_Status DEFAULT ('A'),
    XLastUser    VARCHAR(20)  NULL,
    XLastDate    DATETIME     NULL,
    CONSTRAINT PK_WEB_AccessProfile PRIMARY KEY (ProfileCode)
);
GO

CREATE TABLE dbo.WEB_AccessProfileMenu (
    ProfileCode  VARCHAR(30) NOT NULL,
    MenuCode     VARCHAR(60) NOT NULL,
    CONSTRAINT PK_WEB_AccessProfileMenu PRIMARY KEY (ProfileCode, MenuCode),
    CONSTRAINT FK_WEB_APM_Profile FOREIGN KEY (ProfileCode)
        REFERENCES dbo.WEB_AccessProfile (ProfileCode),
    CONSTRAINT FK_WEB_APM_Menu FOREIGN KEY (MenuCode)
        REFERENCES dbo.WEB_MenuOption (MenuCode)
);
GO

CREATE TABLE dbo.WEB_UserAccessProfile (
    UserID       VARCHAR(20) NOT NULL,
    ProfileCode  VARCHAR(30) NOT NULL,
    XLastUser    VARCHAR(20) NULL,
    XLastDate    DATETIME    NULL,
    CONSTRAINT PK_WEB_UserAccessProfile PRIMARY KEY (UserID),
    CONSTRAINT FK_WEB_UAP_Profile FOREIGN KEY (ProfileCode)
        REFERENCES dbo.WEB_AccessProfile (ProfileCode)
);
GO
