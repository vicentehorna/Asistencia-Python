/*
    Selector de ubigeo (distritos de Perú) para ficha del trabajador.
    Usado por: GET /api/selectores/ubigeo y /api/ficha-datos/ubigeo

    @cia      — opcional (filtra SY_Localite.Company si tiene valor).
              Si la compañía no tiene catálogo propio, usa BGT (o la primera
              compañía con data) como catálogo geográfico compartido.
    @busqueda — nombre distrito/provincia/departamento o código PDT.
    @top      — máximo de filas (default 40).
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_pr_selectorubigeo_web]
    @cia      VARCHAR(10)  = NULL,
    @busqueda VARCHAR(100) = '',
    @top      INT          = 40
AS
BEGIN
    SET NOCOUNT ON;

    SET @cia = NULLIF(LTRIM(RTRIM(ISNULL(@cia, ''))), '');
    SET @busqueda = LTRIM(RTRIM(ISNULL(@busqueda, '')));
    IF ISNULL(@top, 0) <= 0 SET @top = 40;
    IF @top > 100 SET @top = 100;

    DECLARE @cia_filtro VARCHAR(10) = @cia;
    IF @cia_filtro IS NOT NULL
       AND NOT EXISTS (
            SELECT 1 FROM SY_Localite l0 (NOLOCK)
            WHERE LTRIM(RTRIM(l0.Company)) = @cia_filtro
       )
    BEGIN
        IF EXISTS (SELECT 1 FROM SY_Localite (NOLOCK) WHERE LTRIM(RTRIM(Company)) = 'BGT')
            SET @cia_filtro = 'BGT';
        ELSE
            SELECT TOP 1 @cia_filtro = LTRIM(RTRIM(Company))
            FROM SY_Localite (NOLOCK)
            WHERE ISNULL(LTRIM(RTRIM(Company)), '') <> ''
            ORDER BY Company;
    END

    SELECT TOP (@top)
        LTRIM(RTRIM(l.Localite)) AS id,
        LTRIM(RTRIM(
            ISNULL(d.Name, '') + ' / ' +
            ISNULL(p.Name, '') + ' / ' +
            ISNULL(l.Name, '')
        )) AS text,
        LTRIM(RTRIM(ISNULL(l.Name, ''))) AS distrito,
        LTRIM(RTRIM(ISNULL(p.Name, ''))) AS provincia,
        LTRIM(RTRIM(ISNULL(d.Name, ''))) AS departamento,
        LTRIM(RTRIM(ISNULL(l.pdt, ''))) AS ubigeo,
        LTRIM(RTRIM(ISNULL(l.Province, ''))) AS province,
        LTRIM(RTRIM(ISNULL(p.Department, ''))) AS department,
        LTRIM(RTRIM(ISNULL(d.Country, ''))) AS country
    FROM SY_Localite l (NOLOCK)
        INNER JOIN SY_Province p (NOLOCK)
            ON p.Province = l.Province
        INNER JOIN SY_Department d (NOLOCK)
            ON d.Department = p.Department
        INNER JOIN SY_Country c (NOLOCK)
            ON c.Country = d.Country
    WHERE UPPER(LTRIM(RTRIM(ISNULL(c.Name, '')))) = 'PERU'
      AND (
            @cia_filtro IS NULL
         OR LTRIM(RTRIM(ISNULL(l.Company, ''))) = ''
         OR LTRIM(RTRIM(l.Company)) = @cia_filtro
      )
      AND (
            @busqueda = ''
         OR l.Name COLLATE Latin1_General_CI_AI LIKE '%' + @busqueda + '%'
         OR p.Name COLLATE Latin1_General_CI_AI LIKE '%' + @busqueda + '%'
         OR d.Name COLLATE Latin1_General_CI_AI LIKE '%' + @busqueda + '%'
         OR LTRIM(RTRIM(ISNULL(l.pdt, ''))) LIKE @busqueda + '%'
         OR (
                ISNULL(d.Name, '') + ' / ' +
                ISNULL(p.Name, '') + ' / ' +
                ISNULL(l.Name, '')
            ) COLLATE Latin1_General_CI_AI LIKE '%' + @busqueda + '%'
      )
    ORDER BY d.Name, p.Name, l.Name;
END
GO
