/*
  Tabla: dbo.CA_Feriados
  Uso: Pantalla Feriados (database.get_feriados_lista / guardar_feriado)
       y exclusión de faltas en sp_ca_procesarasistencia_web.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.CA_Feriados', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CA_Feriados] (
        [IdFeriado]     INT IDENTITY(1, 1) NOT NULL,
        [Fecha]         DATETIME NOT NULL,
        [Motivo]        VARCHAR(255) NOT NULL,
        [EsRecuperable] BIT NULL,
        [XLastUser]     VARCHAR(20) NULL,
        [XLastDate]     DATETIME NULL,
        CONSTRAINT [PK_CA_Feriados] PRIMARY KEY CLUSTERED ([IdFeriado] ASC)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.CA_Feriados')
      AND name = N'IX_CA_Feriados_Fecha'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CA_Feriados_Fecha]
        ON [dbo].[CA_Feriados] ([Fecha] ASC);
END;
GO
