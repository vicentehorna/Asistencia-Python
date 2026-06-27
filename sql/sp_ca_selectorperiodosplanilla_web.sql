/*
  Procedimiento: sp_ca_selectorperiodosplanilla_web
  Uso: Consolidado de Asistencia — selector de periodos para Registro Planillas
  Parámetros: @cia
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_ca_selectorperiodosplanilla_web]
    @cia VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SET @cia = LTRIM(RTRIM(ISNULL(@cia, '')));

    SELECT DISTINCT p.PRPeriod
    FROM PR_Period p
    WHERE p.Company = @cia
    ORDER BY p.PRPeriod DESC;
END
GO
