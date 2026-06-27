/*
  Tabla: dbo.CA_RegularizacionFalta
  Uso: Auditoría de regularización de faltas (encargo de empresa) desde Consolidado de Asistencia.
       Por cada día regularizado se crean marcas de entrada/salida según horario.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE [dbo].[CA_RegularizacionFalta] (
    [IdRegularizacion] INT IDENTITY(1, 1) NOT NULL,
    [company]          CHAR(4) NOT NULL,
    [Person]           VARCHAR(20) NOT NULL,
    [Fecha]            DATE NOT NULL,
    [IdHorario]        INT NULL,
    [HoraEntrada]      DATETIME NOT NULL,
    [HoraSalida]       DATETIME NOT NULL,
    [Comentario]       VARCHAR(255) NULL,
    [xlastuser]        VARCHAR(20) NULL,
    [xlastdate]        DATETIME NOT NULL,
    CONSTRAINT [PK_CA_RegularizacionFalta] PRIMARY KEY CLUSTERED ([IdRegularizacion] ASC)
) ON [PRIMARY];
GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_CA_RegularizacionFalta_company_person_fecha]
    ON [dbo].[CA_RegularizacionFalta] ([company] ASC, [Person] ASC, [Fecha] ASC);
GO

ALTER TABLE [dbo].[CA_RegularizacionFalta]
    ADD CONSTRAINT [DF_CA_RegularizacionFalta_xlastdate]
    DEFAULT (GETDATE()) FOR [xlastdate];
GO
