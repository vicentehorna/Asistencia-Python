/*
  Procedimiento: sp_ca_listaaccesomarcador_web
  Uso: Seguridad > Acceso al Marcador (GET /api/seguridad/acceso-marcador/lista)
  Parámetros: @cia
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_ca_listaaccesomarcador_web]
    @cia VARCHAR(4)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Person,
        p.Name,
        LTRIM(RTRIM(ISNULL(p.pinAcceso, ''))) AS PinAcceso,
        CASE WHEN b.Person IS NOT NULL THEN 1 ELSE 0 END AS TieneBiometria,
        b.LastUpdate AS BiometriaLastUpdate,
        LTRIM(RTRIM(ISNULL(b.Status, ''))) AS BiometriaStatus,
        DATALENGTH(b.Face_Template) AS BiometriaTemplateBytes
    FROM SY_Person AS p
    INNER JOIN PR_Employee AS e
        ON p.Person = e.Person
       AND e.Company = @cia
       AND e.Status = 'N'
    LEFT JOIN SY_Person_biometry AS b
        ON b.Person = p.Person
    ORDER BY p.Name;
END;
GO
