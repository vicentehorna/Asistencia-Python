CREATE OR ALTER PROCEDURE [dbo].[sp_web_asignar_user_access_profile_web]
    @userid      VARCHAR(20),
    @profilecode VARCHAR(30) = NULL,
    @xlastuser   VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @userid = LTRIM(RTRIM(ISNULL(@userid, '')));
    SET @profilecode = NULLIF(UPPER(LTRIM(RTRIM(ISNULL(@profilecode, '')))), '');
    SET @xlastuser = NULLIF(LTRIM(RTRIM(ISNULL(@xlastuser, ''))), '');

    IF @userid = ''
    BEGIN
        RAISERROR('Indique el usuario.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM SY_User (NOLOCK) WHERE UserID = @userid)
    BEGIN
        RAISERROR('El usuario no existe.', 16, 1);
        RETURN;
    END;

    /* profilecode NULL o vacio = quitar asignacion (vuelve a unrestricted) */
    IF @profilecode IS NULL
    BEGIN
        DELETE FROM WEB_UserAccessProfile WHERE UserID = @userid;
        SELECT
            @userid AS userid,
            CAST(NULL AS VARCHAR(30)) AS profilecode,
            'Asignacion de perfil eliminada. El usuario vera todo el menu.' AS mensaje;
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM WEB_AccessProfile (NOLOCK)
        WHERE ProfileCode = @profilecode AND Status = 'A'
    )
    BEGIN
        RAISERROR('El perfil indicado no existe.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM WEB_UserAccessProfile (NOLOCK) WHERE UserID = @userid)
    BEGIN
        UPDATE WEB_UserAccessProfile
        SET ProfileCode = @profilecode,
            XLastUser = @xlastuser,
            XLastDate = GETDATE()
        WHERE UserID = @userid;
    END
    ELSE
    BEGIN
        INSERT INTO WEB_UserAccessProfile (UserID, ProfileCode, XLastUser, XLastDate)
        VALUES (@userid, @profilecode, @xlastuser, GETDATE());
    END;

    SELECT
        @userid AS userid,
        @profilecode AS profilecode,
        'Perfil asignado correctamente.' AS mensaje;
END
GO
