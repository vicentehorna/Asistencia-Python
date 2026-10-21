/*
  Procedimiento: sp_pr_listadomarcas_web
  Uso: Gestión de Marcas (database.get_listado_marcas / api/marcas/listar)
  Parámetros: @cia, @Fechainicio, @FechaFin, @person ('0' = todos los trabajadores)
  GPS: Latitud/Longitud/PC solo existen en hm_quimica. En esa BD se leen con SQL
       dinámico; en cualquier otra BD se devuelve NULL para no referenciar
       columnas inexistentes (la pantalla muestra "Sin GPS").
  Empresa: se filtra por RegistroAsistencia.company (la empresa real de la marca).
       Un trabajador puede ser empleado en varias empresas; el JOIN con PR_Employee
       por sí solo traía marcas de otras empresas. Las marcas antiguas sin company
       (NULL/vacío) se aceptan vía el empleado, igual que en Procesar Asistencia.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_pr_listadomarcas_web]
    @cia          CHAR(4),
    @Fechainicio  DATETIME,
    @FechaFin     DATETIME,
    @person       VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_NAME() = N'hm_quimica'
       AND COL_LENGTH('dbo.RegistroAsistencia', 'Latitud') IS NOT NULL
       AND COL_LENGTH('dbo.RegistroAsistencia', 'Longitud') IS NOT NULL
       AND COL_LENGTH('dbo.RegistroAsistencia', 'PC') IS NOT NULL
    BEGIN
        EXEC sp_executesql
            N'SELECT
                R.IdRegistro,
                P.Person AS DNI,
                P.Name AS Nombre,
                CASE ((DATEPART(WEEKDAY, CONVERT(DATE, R.FechaHoraIngreso)) + @@DATEFIRST - 2) % 7) + 1
                    WHEN 1 THEN ''LU''
                    WHEN 2 THEN ''MA''
                    WHEN 3 THEN ''MI''
                    WHEN 4 THEN ''JU''
                    WHEN 5 THEN ''VI''
                    WHEN 6 THEN ''SA''
                    ELSE ''DO''
                END AS diasemana,
                R.FechaHoraIngreso AS FechaHoraIngreso,
                CONVERT(VARCHAR(5), R.FechaHoraIngreso, 108) AS hora,
                PR_Position.Description AS cargo,
                R.RutaFoto,
                R.Latitud,
                R.Longitud,
                R.PC
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
              AND (@person = ''0'' OR R.Person = @person)
              AND (R.company = @cia OR NULLIF(LTRIM(RTRIM(R.company)), '''') IS NULL)
              AND R.estado = ''A''
            ORDER BY P.Name, R.FechaHoraIngreso',
            N'@cia CHAR(4), @Fechainicio DATETIME, @FechaFin DATETIME, @person VARCHAR(20)',
            @cia = @cia, @Fechainicio = @Fechainicio, @FechaFin = @FechaFin, @person = @person;
        RETURN;
    END;

    SELECT
        R.IdRegistro,
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
        R.RutaFoto,
        CAST(NULL AS DECIMAL(10, 7)) AS Latitud,
        CAST(NULL AS DECIMAL(10, 7)) AS Longitud,
        CAST(NULL AS VARCHAR(255)) AS PC
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
      AND (R.company = @cia OR NULLIF(LTRIM(RTRIM(R.company)), '') IS NULL)
      AND R.estado = 'A'
    ORDER BY P.Name, R.FechaHoraIngreso;
END;
GO
