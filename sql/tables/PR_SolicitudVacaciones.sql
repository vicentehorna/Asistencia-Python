/*
  Tabla: dbo.PR_SolicitudVacaciones
  Origen funcional: PortalMinero / hm_safari
  Estados: P=Pendiente, A=Aprobado, R=Rechazado

  Nota de esquema:
  - hm_safari: PK Id IDENTITY
  - hm_quimica (y varios clientes Softland): PK (Person, Company, Line)
  La app detecta Id vs Line en runtime.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.PR_SolicitudVacaciones', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[PR_SolicitudVacaciones] (
        [Person]        VARCHAR(20)  NOT NULL,
        [Company]       VARCHAR(4)   NOT NULL,
        [Line]          INT          NOT NULL,
        [DateBegin]     DATETIME     NULL,
        [DateEnd]       DATETIME     NULL,
        [Days]          INT          NULL,
        [status]        CHAR(1)      NULL,
        [xlastuser]     VARCHAR(20)  NULL,
        [xlastdate]     VARCHAR(20)  NULL,
        [registerdate]  DATETIME     NULL,
        [ApprovalDate]  DATETIME     NULL,
        [ApprovalUser]  VARCHAR(20)  NULL,
        [Comments]      VARCHAR(255) NULL,
        [ControlYear]   VARCHAR(4)   NULL,
        [NombreSustento] VARCHAR(255) NULL,
        CONSTRAINT [PK_PR_SolicitudVacaciones]
            PRIMARY KEY CLUSTERED ([Person] ASC, [Company] ASC, [Line] ASC)
    );
END
GO

IF COL_LENGTH('dbo.PR_SolicitudVacaciones', 'NombreSustento') IS NULL
    AND OBJECT_ID('dbo.PR_SolicitudVacaciones', 'U') IS NOT NULL
    ALTER TABLE dbo.PR_SolicitudVacaciones ADD NombreSustento VARCHAR(255) NULL;
GO
