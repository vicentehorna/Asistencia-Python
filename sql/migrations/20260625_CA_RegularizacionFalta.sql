/*
  Migración: tabla CA_RegularizacionFalta (regularización de faltas desde consolidado)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.CA_RegularizacionFalta', N'U') IS NULL
BEGIN
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

    CREATE UNIQUE NONCLUSTERED INDEX [UX_CA_RegularizacionFalta_company_person_fecha]
        ON [dbo].[CA_RegularizacionFalta] ([company] ASC, [Person] ASC, [Fecha] ASC);

    ALTER TABLE [dbo].[CA_RegularizacionFalta]
        ADD CONSTRAINT [DF_CA_RegularizacionFalta_xlastdate]
        DEFAULT (GETDATE()) FOR [xlastdate];
END
GO
