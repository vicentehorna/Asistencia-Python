CREATE OR ALTER PROCEDURE [dbo].[sp_web_listar_access_profiles_web]
    @busqueda VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @busqueda = NULLIF(LTRIM(RTRIM(ISNULL(@busqueda, ''))), '');

    SELECT
        p.ProfileCode AS profilecode,
        p.Name AS name,
        p.FlagAdmin AS flagadmin,
        p.Status AS status,
        ISNULL((
            SELECT COUNT(*)
            FROM WEB_AccessProfileMenu pm (NOLOCK)
            WHERE pm.ProfileCode = p.ProfileCode
        ), 0) AS menus,
        ISNULL((
            SELECT COUNT(*)
            FROM WEB_UserAccessProfile u (NOLOCK)
            WHERE u.ProfileCode = p.ProfileCode
        ), 0) AS usuarios
    FROM WEB_AccessProfile p (NOLOCK)
    WHERE p.Status = 'A'
      AND (
            @busqueda IS NULL
         OR p.ProfileCode LIKE '%' + @busqueda + '%'
         OR p.Name LIKE '%' + @busqueda + '%'
      )
    ORDER BY CASE WHEN p.FlagAdmin = 'Y' THEN 0 ELSE 1 END, p.ProfileCode;
END
GO
