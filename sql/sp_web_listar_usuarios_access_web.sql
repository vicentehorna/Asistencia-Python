CREATE OR ALTER PROCEDURE [dbo].[sp_web_listar_usuarios_access_web]
    @busqueda VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @busqueda = NULLIF(LTRIM(RTRIM(ISNULL(@busqueda, ''))), '');

    SELECT
        u.UserID AS userid,
        LTRIM(RTRIM(ISNULL(p.Name, ''))) AS nombre,
        uap.ProfileCode AS profilecode,
        ISNULL(ap.Name, '') AS profilename,
        ISNULL(ap.FlagAdmin, 'N') AS flagadmin
    FROM SY_User u (NOLOCK)
    INNER JOIN SY_UserProfile up (NOLOCK)
        ON up.UserID = u.UserID
    INNER JOIN SY_Profile pr (NOLOCK)
        ON pr.Profile = up.Profile
       AND pr.Profile = 'EMPWEB'
    LEFT JOIN SY_Person p (NOLOCK)
        ON p.UserID = u.UserID
    LEFT JOIN WEB_UserAccessProfile uap (NOLOCK)
        ON uap.UserID = u.UserID
    LEFT JOIN WEB_AccessProfile ap (NOLOCK)
        ON ap.ProfileCode = uap.ProfileCode
    WHERE (
            @busqueda IS NULL
         OR u.UserID LIKE '%' + @busqueda + '%'
         OR p.Name LIKE '%' + @busqueda + '%'
         OR uap.ProfileCode LIKE '%' + @busqueda + '%'
      )
    ORDER BY u.UserID;
END
GO
