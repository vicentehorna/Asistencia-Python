/*
  Procedimiento: sp_pr_listadomarcas_web
  Uso: Gestión de Marcas (database.get_listado_marcas / api/marcas/listar)
  Parámetros: @cia, @Fechainicio, @FechaFin, @person ('0' = todos los trabajadores)
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE [dbo].[sp_pr_listadomarcas_web]
    @cia          CHAR(4),
    @Fechainicio  DATETIME,
    @FechaFin     DATETIME,
    @person       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        P.Person AS DNI,
        P.Name AS Nombre,
        /* Lunes=1 … Domingo=7, independiente de @@DATEFIRST del servidor */
        CASE ((DATEPART(WEEKDAY, CONVERT(DATE, R.FechaHoraIngreso)) + @@DATEFIRST - 2) % 7) + 1
            WHEN 1 THEN 'LU'
            WHEN 2 THEN 'MA'
            WHEN 3 THEN 'MI'
            WHEN 4 THEN 'JU'
            WHEN 5 THEN 'VI'
            WHEN 6 THEN 'SA'
            ELSE 'DO'
        END AS diasemana,
        R.FechaHoraIngreso AS FechaHoraIngreso,
        CONVERT(VARCHAR(5), R.FechaHoraIngreso, 108) AS hora,
        PR_Position.Description AS cargo,
        R.RutaFoto
    FROM RegistroAsistencia R
    INNER JOIN SY_Person P
        ON R.Person = P.Person
    INNER JOIN PR_Employee E
        ON P.Person = E.Person
       AND E.Company = @cia
    LEFT JOIN PR_Position
        ON E.Position = PR_Position.Position
    WHERE CONVERT(VARCHAR(8), R.FechaHoraIngreso, 112)
          BETWEEN CONVERT(VARCHAR(8), @Fechainicio, 112)
              AND CONVERT(VARCHAR(8), @FechaFin, 112)
      AND (@person = '0' OR R.Person = @person)
    ORDER BY P.Name, R.FechaHoraIngreso;
END;
GO
