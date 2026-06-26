/*
  Migración: columna estado en RegistroAsistencia
  A = activo (visible en Gestión de Marcas), I = inactivo (oculto)
  Ejecutar una vez en bases existentes.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.RegistroAsistencia', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[RegistroAsistencia]
        ADD [estado] CHAR(1) NOT NULL
            CONSTRAINT [DF_RegistroAsistencia_estado] DEFAULT ('A') WITH VALUES;
END;
GO
