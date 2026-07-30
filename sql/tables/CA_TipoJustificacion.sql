/*
  Tabla: dbo.CA_TipoJustificacion
  Uso: Maestro de tipos de justificación (Justificaciones / Procesar Asistencia)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.CA_TipoJustificacion', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CA_TipoJustificacion] (
        [IdJustificacion]   INT IDENTITY(1, 1) NOT NULL,
        [Descripcion]       VARCHAR(255) NULL,
        [Abreviatura]       VARCHAR(20) NULL,
        [EsDiaCompleto]     BIT NULL,
        [PagaHaber]         BIT NULL,
        [RequiereSustento]  BIT NULL,
        [xlastuser]         VARCHAR(20) NULL,
        [xlastdate]         DATETIME NULL,
        CONSTRAINT [PK_CA_TipoJustificacion] PRIMARY KEY CLUSTERED ([IdJustificacion] ASC)
    );
END;
GO
