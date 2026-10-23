CREATE OR ALTER PROCEDURE [dbo].[sp_web_eliminar_access_profile_web]
    @profilecode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @profilecode = UPPER(LTRIM(RTRIM(ISNULL(@profilecode, ''))));

    IF @profilecode = ''
    BEGIN
        RAISERROR('Indique el perfil a eliminar.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM WEB_AccessProfile (NOLOCK)
        WHERE ProfileCode = @profilecode AND FlagAdmin = 'Y'
    )
    BEGIN
        RAISERROR('No se puede eliminar el perfil administrador.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM WEB_UserAccessProfile (NOLOCK)
        WHERE ProfileCode = @profilecode
    )
    BEGIN
        RAISERROR('No se puede eliminar: el perfil esta asignado a usuarios.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM WEB_AccessProfileMenu WHERE ProfileCode = @profilecode;
        DELETE FROM WEB_AccessProfile WHERE ProfileCode = @profilecode;
        COMMIT TRANSACTION;

        SELECT @profilecode AS profilecode, 'Perfil eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
