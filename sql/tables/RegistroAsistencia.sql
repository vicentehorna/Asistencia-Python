/*
  Tabla: dbo.RegistroAsistencia
  Uso: Gestión de Marcas (consulta vía sp_pr_listadomarcas_web, alta manual en api/marcas/manual)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE [dbo].[RegistroAsistencia] (
    [IdRegistro]       INT IDENTITY(1, 1) NOT NULL,
    [IdTrabajador]     INT NOT NULL,
    [FechaHoraIngreso] DATETIME NOT NULL,
    [RutaFoto]         VARCHAR(255) NULL,
    [Person]           VARCHAR(20) NULL,
    [company]          CHAR(4) NULL,
    [xlastuser]        VARCHAR(20) NULL,
    [xlastdate]        DATETIME NULL,
    [flagmanual]       CHAR(1) NOT NULL,
    [MotivoManual]     VARCHAR(255) NULL,
    [estado]           CHAR(1) NOT NULL,
    CONSTRAINT [PK_RegistroAsistencia] PRIMARY KEY CLUSTERED ([IdRegistro] ASC)
        WITH (
            PAD_INDEX = OFF,
            STATISTICS_NORECOMPUTE = OFF,
            IGNORE_DUP_KEY = OFF,
            ALLOW_ROW_LOCKS = ON,
            ALLOW_PAGE_LOCKS = ON
        ) ON [PRIMARY]
) ON [PRIMARY];
GO

ALTER TABLE [dbo].[RegistroAsistencia]
    ADD CONSTRAINT [DF_RegistroAsistencia_FechaHoraIngreso]
    DEFAULT (GETDATE()) FOR [FechaHoraIngreso];
GO

ALTER TABLE [dbo].[RegistroAsistencia]
    ADD CONSTRAINT [DF_RegistroAsistencia_flagmanual]
    DEFAULT ('N') FOR [flagmanual];
GO

ALTER TABLE [dbo].[RegistroAsistencia]
    ADD CONSTRAINT [DF_RegistroAsistencia_estado]
    DEFAULT ('A') FOR [estado];
GO

ALTER TABLE [dbo].[RegistroAsistencia] WITH CHECK
    ADD CONSTRAINT [FK_RegistroAsistencia_Trabajadores]
    FOREIGN KEY ([IdTrabajador])
    REFERENCES [dbo].[Trabajadores] ([IdTrabajador]);
GO
