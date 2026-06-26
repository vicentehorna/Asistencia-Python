/*
  Procedimiento: sp_pr_selectorcompanias_web
  Uso: Selector de compañías (Gestión de Marcas, alertas, horarios, reportes, etc.)
  Parámetros: ninguno
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_pr_selectorcompanias_web]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Company,
        description
    FROM SY_Company
    WHERE status = 'A'
    ORDER BY Company;
END;
GO
