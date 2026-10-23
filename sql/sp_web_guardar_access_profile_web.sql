/*
    Alta / edicion de perfil web + reemplazo de menus.
    @menus: lista separada por comas de MenuCode.
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_web_guardar_access_profile_web]
    @modo        CHAR(1),
    @profilecode VARCHAR(30),
    @name        VARCHAR(120),
    @menus       VARCHAR(MAX) = NULL,
    @xlastuser   VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @flagadmin CHAR(1) = 'N';
    DECLARE @xmlMenus XML;

    SET @modo = UPPER(LTRIM(RTRIM(ISNULL(@modo, ''))));
    SET @profilecode = UPPER(LTRIM(RTRIM(ISNULL(@profilecode, ''))));
    SET @name = LTRIM(RTRIM(ISNULL(@name, '')));
    SET @menus = LTRIM(RTRIM(ISNULL(@menus, '')));
    SET @xlastuser = NULLIF(LTRIM(RTRIM(ISNULL(@xlastuser, ''))), '');

    IF @modo NOT IN ('I', 'U')
    BEGIN
        RAISERROR('Modo de operacion invalido.', 16, 1);
        RETURN;
    END;

    IF @profilecode = '' OR @name = ''
    BEGIN
        RAISERROR('Indique codigo y nombre del perfil.', 16, 1);
        RETURN;
    END;

    IF @modo = 'I' AND EXISTS (
        SELECT 1 FROM WEB_AccessProfile (NOLOCK) WHERE ProfileCode = @profilecode
    )
    BEGIN
        RAISERROR('Ya existe un perfil con ese codigo.', 16, 1);
        RETURN;
    END;

    IF @modo = 'U' AND NOT EXISTS (
        SELECT 1 FROM WEB_AccessProfile (NOLOCK) WHERE ProfileCode = @profilecode
    )
    BEGIN
        RAISERROR('No se encontro el perfil a actualizar.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @modo = 'I'
        BEGIN
            INSERT INTO WEB_AccessProfile (
                ProfileCode, Name, FlagAdmin, Status, XLastUser, XLastDate
            )
            VALUES (
                @profilecode, @name, 'N', 'A', @xlastuser, GETDATE()
            );
        END
        ELSE
        BEGIN
            SELECT @flagadmin = FlagAdmin
            FROM WEB_AccessProfile (NOLOCK)
            WHERE ProfileCode = @profilecode;

            UPDATE WEB_AccessProfile
            SET Name = @name,
                XLastUser = @xlastuser,
                XLastDate = GETDATE()
            WHERE ProfileCode = @profilecode;
        END;

        DELETE FROM WEB_AccessProfileMenu WHERE ProfileCode = @profilecode;

        IF @menus <> ''
        BEGIN
            /* Compatible con SQL Server < 2016 / compatibility < 130 (sin STRING_SPLIT) */
            SET @xmlMenus = CAST(
                '<root><l>' + REPLACE(@menus, ',', '</l><l>') + '</l></root>' AS XML
            );

            INSERT INTO WEB_AccessProfileMenu (ProfileCode, MenuCode)
            SELECT DISTINCT
                @profilecode,
                LTRIM(RTRIM(x.value('.', 'VARCHAR(50)')))
            FROM @xmlMenus.nodes('/root/l') AS T(x)
            WHERE NULLIF(LTRIM(RTRIM(x.value('.', 'VARCHAR(50)'))), '') IS NOT NULL
              AND EXISTS (
                    SELECT 1
                    FROM WEB_MenuOption m (NOLOCK)
                    WHERE m.MenuCode = LTRIM(RTRIM(x.value('.', 'VARCHAR(50)')))
                      AND m.Status = 'A'
              );
        END;

        /* ADMIN siempre conserva FlagAdmin y opciones de administración de perfiles */
        IF EXISTS (
            SELECT 1 FROM WEB_AccessProfile (NOLOCK)
            WHERE ProfileCode = @profilecode AND FlagAdmin = 'Y'
        )
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM WEB_AccessProfileMenu (NOLOCK)
                WHERE ProfileCode = @profilecode AND MenuCode = 'perfiles_acceso'
            )
            AND EXISTS (SELECT 1 FROM WEB_MenuOption WHERE MenuCode = 'perfiles_acceso')
            BEGIN
                INSERT INTO WEB_AccessProfileMenu (ProfileCode, MenuCode)
                VALUES (@profilecode, 'perfiles_acceso');
            END;

            IF NOT EXISTS (
                SELECT 1 FROM WEB_AccessProfileMenu (NOLOCK)
                WHERE ProfileCode = @profilecode AND MenuCode = 'asignar_perfiles'
            )
            AND EXISTS (SELECT 1 FROM WEB_MenuOption WHERE MenuCode = 'asignar_perfiles')
            BEGIN
                INSERT INTO WEB_AccessProfileMenu (ProfileCode, MenuCode)
                VALUES (@profilecode, 'asignar_perfiles');
            END;
        END;

        COMMIT TRANSACTION;

        SELECT
            @profilecode AS profilecode,
            'Perfil guardado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
