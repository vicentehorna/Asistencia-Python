/*
  Listado de solicitudes de vacaciones para aprobación.
  Esquema Softland (Person, Company, Line) — hm_quimica.
  Usado por: POST /reporte_aprobar_vacaciones
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_pr_aprobarvacaciones_web]
(
    @cia VARCHAR(20),
    @person VARCHAR(20),
    @dni VARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON;

    IF RTRIM(ISNULL(@person, '')) = '' SET @person = '0';
    IF @dni IS NULL SET @dni = '';

    SELECT
        SY_Person.Person,
        SY_Person.Name,
        ControlYear,
        DateBegin,
        DateEnd,
        PR_SolicitudVacaciones.status,
        ApprovalDate,
        PR_SolicitudVacaciones.Line AS id,
        CAST(NULL AS VARCHAR(255)) AS NombreSustento
    FROM PR_SolicitudVacaciones
    INNER JOIN SY_Person
        ON PR_SolicitudVacaciones.Person = SY_Person.Person
       AND PR_SolicitudVacaciones.Company = @cia
    WHERE (@person = '0' OR PR_SolicitudVacaciones.Person = @person)
      AND (
            @dni = ''
            OR SY_Person.Person LIKE '%' + @dni + '%'
            OR ISNULL(SY_Person.DocumentNumber, '') LIKE '%' + @dni + '%'
          )
    ORDER BY 2, DateBegin;
END
GO
