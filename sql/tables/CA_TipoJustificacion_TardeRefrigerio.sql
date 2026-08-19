/*
  Columna: CA_TipoJustificacion.TardeRefrigerio
  Uso: maestro Tipos de Justificación (hm_quimica). Marca tipos que justifican
       solo el exceso de almuerzo (>60 min), no la tardanza de entrada.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.CA_TipoJustificacion', N'TardeRefrigerio') IS NULL
BEGIN
    ALTER TABLE [dbo].[CA_TipoJustificacion]
        ADD [TardeRefrigerio] BIT NULL
            CONSTRAINT [DF_CA_TipoJustificacion_TardeRefrigerio] DEFAULT (0);
END;
GO
