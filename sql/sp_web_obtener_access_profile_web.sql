CREATE OR ALTER PROCEDURE [dbo].[sp_web_obtener_access_profile_web]
    @profilecode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    SET @profilecode = LTRIM(RTRIM(ISNULL(@profilecode, '')));

    SELECT
        p.ProfileCode AS profilecode,
        p.Name AS name,
        p.FlagAdmin AS flagadmin,
        p.Status AS status
    FROM WEB_AccessProfile p (NOLOCK)
    WHERE p.ProfileCode = @profilecode;

    SELECT
        m.MenuCode AS menucode,
        m.Title AS title,
        m.ParentCode AS parentcode,
        m.SortOrder AS sortorder,
        CASE WHEN pm.MenuCode IS NULL THEN 0 ELSE 1 END AS selected
    FROM WEB_MenuOption m (NOLOCK)
    LEFT JOIN WEB_AccessProfileMenu pm (NOLOCK)
        ON pm.MenuCode = m.MenuCode
       AND pm.ProfileCode = @profilecode
    WHERE m.Status = 'A'
    ORDER BY m.SortOrder, m.Title;
END
GO
