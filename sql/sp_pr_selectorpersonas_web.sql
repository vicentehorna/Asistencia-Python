/*
  Procedimiento: sp_pr_selectorpersonas_web
  Uso: Selector de trabajadores por compañía (Gestión de Marcas, reportes, etc.)
  Parámetros: @cia
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_pr_selectorpersonas_web]
    @cia VARCHAR(4)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        PR_Employee.Person,
        SY_Person.Name
    FROM SY_Person
    INNER JOIN PR_Employee
        ON SY_Person.Person = PR_Employee.Person
       AND PR_Employee.Status = 'N'
       AND PR_Employee.Company = @cia
    ORDER BY SY_Person.Name;
END;
GO
