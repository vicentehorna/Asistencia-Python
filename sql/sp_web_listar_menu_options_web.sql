CREATE OR ALTER PROCEDURE [dbo].[sp_web_listar_menu_options_web]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        m.MenuCode AS menucode,
        m.Title AS title,
        m.ParentCode AS parentcode,
        m.SortOrder AS sortorder,
        m.Endpoint AS endpoint,
        m.RoutePrefix AS routeprefix
    FROM WEB_MenuOption m (NOLOCK)
    WHERE m.Status = 'A'
    ORDER BY m.SortOrder, m.Title;
END
GO
