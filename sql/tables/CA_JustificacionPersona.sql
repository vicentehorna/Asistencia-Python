/*
  Tabla: dbo.CA_JustificacionPersona
  Uso: Justificaciones por persona (pantalla Justificaciones / Procesar Asistencia)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.CA_JustificacionPersona', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CA_JustificacionPersona] (
        [Id]                INT IDENTITY(1, 1) NOT NULL,
        [company]           VARCHAR(10) NULL,
        [Person]            VARCHAR(20) NULL,
        [IdJustificacion]   INT NOT NULL,
        [FechaInicio]       DATETIME NOT NULL,
        [FechaFin]          DATETIME NOT NULL,
        [HoraInicio]        VARCHAR(5) NULL,
        [HoraFin]           VARCHAR(5) NULL,
        [Comentario]        VARCHAR(255) NULL,
        [RutaSustento]      VARCHAR(255) NULL,
        [Estado]            CHAR(1) NULL,
        [xlastuser]         VARCHAR(20) NULL,
        [xlastdate]         DATETIME NULL,
        CONSTRAINT [PK_CA_JustificacionPersona] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.CA_JustificacionPersona')
      AND name = N'IX_CA_JustificacionPersona_PersonFecha'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CA_JustificacionPersona_PersonFecha]
        ON [dbo].[CA_JustificacionPersona] ([Person], [company], [FechaInicio], [FechaFin]);
END;
GO
