/*
    Menus efectivos del usuario.
    Resultset 1: flags unrestricted / web_admin / profilecode
    Resultset 2: MenuCode permitidos (vacio si unrestricted)
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_web_obtener_menus_usuario_web]
    @userid VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @profilecode VARCHAR(30) = NULL;
    DECLARE @flagadmin CHAR(1) = 'N';
    DECLARE @unrestricted INT = 0;

    SET @userid = LTRIM(RTRIM(ISNULL(@userid, '')));

    /* Si no existen las tablas, el caller Python trata como unrestricted. */
    IF OBJECT_ID('dbo.WEB_UserAccessProfile', 'U') IS NULL
    BEGIN
        SELECT
            1 AS unrestricted,
            0 AS web_admin,
            CAST(NULL AS VARCHAR(30)) AS profilecode;
        SELECT CAST(NULL AS VARCHAR(60)) AS menucode WHERE 1 = 0;
        RETURN;
    END;

    SELECT
        @profilecode = uap.ProfileCode,
        @flagadmin = ISNULL(ap.FlagAdmin, 'N')
    FROM WEB_UserAccessProfile uap (NOLOCK)
    INNER JOIN WEB_AccessProfile ap (NOLOCK)
        ON ap.ProfileCode = uap.ProfileCode
       AND ap.Status = 'A'
    WHERE uap.UserID = @userid;

    IF @profilecode IS NULL
    BEGIN
        SET @unrestricted = 1;
        SELECT
            1 AS unrestricted,
            0 AS web_admin,
            CAST(NULL AS VARCHAR(30)) AS profilecode;
        SELECT CAST(NULL AS VARCHAR(60)) AS menucode WHERE 1 = 0;
        RETURN;
    END;

    IF @flagadmin = 'Y'
    BEGIN
        SELECT
            0 AS unrestricted,
            1 AS web_admin,
            @profilecode AS profilecode;

        SELECT m.MenuCode AS menucode
        FROM WEB_MenuOption m (NOLOCK)
        WHERE m.Status = 'A'
        ORDER BY m.SortOrder;
        RETURN;
    END;

    SELECT
        0 AS unrestricted,
        0 AS web_admin,
        @profilecode AS profilecode;

    SELECT pm.MenuCode AS menucode
    FROM WEB_AccessProfileMenu pm (NOLOCK)
    INNER JOIN WEB_MenuOption m (NOLOCK)
        ON m.MenuCode = pm.MenuCode
       AND m.Status = 'A'
    WHERE pm.ProfileCode = @profilecode
    ORDER BY m.SortOrder;
END
GO
