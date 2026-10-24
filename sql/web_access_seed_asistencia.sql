/*
  Seed catálogo de menús de Asistencia en WEB_MenuOption.
  Idempotente (MERGE). No borra menús de Planillas que coexistan en la misma BD.
  Agrega las opciones de Asistencia a todos los perfiles existentes
  (para no cortar acceso a usuarios ya asignados, p.ej. BOLETA).
  Crea perfil ADMIN (FlagAdmin=Y) si no existe.
*/
SET NOCOUNT ON;

MERGE dbo.WEB_MenuOption AS t
USING (VALUES
    ('dashboard',            'Inicio / Dashboard',        NULL,             5,   'dashboard',              '/dashboard',              'A'),
    ('maestro_horarios',     'Maestro de Horarios',       'configuracion',  110, 'maestro_horarios',       '/maestro-horarios',       'A'),
    ('tipos_justificacion',  'Tipos de Justificación',    'configuracion',  120, 'tipos_justificacion',    '/tipos-justificacion',    'A'),
    ('feriados',             'Feriados',                  'configuracion',  130, 'feriados_page',          '/feriados',               'A'),
    ('configurar_alertas',   'Configurar Alertas',        'configuracion',  140, 'configurar_alertas',     '/configurar-alertas',     'A'),
    ('perfiles_acceso',      'Perfiles de acceso',        'configuracion',  150, 'perfiles_acceso_page',   '/perfiles-acceso',        'A'),
    ('asignar_perfiles',     'Asignar perfiles',          'configuracion',  160, 'asignar_perfiles_page',  '/asignar-perfiles',       'A'),
    ('gestion_marcas',       'Gestión de Marcas',         'procesos',       210, 'gestion_marcas',         '/gestion-marcas',         'A'),
    ('justificaciones',      'Justificaciones',           'procesos',       220, 'justificaciones',        '/justificaciones',        'A'),
    ('asignacion_horarios',  'Asignación de Horarios',    'procesos',       230, 'asignacion_horarios',    '/asignacion-horarios',    'A'),
    ('procesar_asistencia',   'Procesar Asistencia',       'procesos',       240, 'procesar_asistencia',     '/procesar-asistencia',     'A'),
    ('reporte_resumen',      'Resumen de Asistencia',     'reportes',       310, 'reporte_resumen',        '/reporte-resumen',        'A'),
    ('reporte_consolidado',  'Consolidado de Asistencia', 'reportes',       320, 'reporte_consolidado',    '/reporte-consolidado',    'A'),
    ('acceso_marcador',      'Acceso al Marcador',        'seguridad',      410, 'acceso_marcador',        '/seguridad/acceso-marcador', 'A'),
    ('solicitud_vacaciones', 'Solicitud de Vacaciones',   'portal_trabajador', 510, 'solicitud_vacaciones_page', '/solicitud-vacaciones', 'A')
) AS s (MenuCode, Title, ParentCode, SortOrder, Endpoint, RoutePrefix, Status)
ON t.MenuCode = s.MenuCode
WHEN MATCHED THEN
    UPDATE SET
        Title = s.Title,
        ParentCode = s.ParentCode,
        SortOrder = s.SortOrder,
        Endpoint = s.Endpoint,
        RoutePrefix = s.RoutePrefix,
        Status = s.Status
WHEN NOT MATCHED THEN
    INSERT (MenuCode, Title, ParentCode, SortOrder, Endpoint, RoutePrefix, Status)
    VALUES (s.MenuCode, s.Title, s.ParentCode, s.SortOrder, s.Endpoint, s.RoutePrefix, s.Status);

IF NOT EXISTS (SELECT 1 FROM dbo.WEB_AccessProfile WHERE ProfileCode = 'ADMIN')
BEGIN
    INSERT INTO dbo.WEB_AccessProfile (ProfileCode, Name, FlagAdmin, Status, XLastUser, XLastDate)
    VALUES ('ADMIN', 'Administrador', 'Y', 'A', 'SYSTEM', GETDATE());
END
ELSE
BEGIN
    UPDATE dbo.WEB_AccessProfile
    SET FlagAdmin = 'Y', Status = 'A', Name = ISNULL(NULLIF(LTRIM(RTRIM(Name)), ''), 'Administrador')
    WHERE ProfileCode = 'ADMIN';
END;

/* ADMIN: todas las opciones de Asistencia */
INSERT INTO dbo.WEB_AccessProfileMenu (ProfileCode, MenuCode)
SELECT 'ADMIN', m.MenuCode
FROM dbo.WEB_MenuOption m
WHERE m.Status = 'A'
  AND m.MenuCode IN (
      'dashboard','maestro_horarios','tipos_justificacion','feriados','configurar_alertas',
      'perfiles_acceso','asignar_perfiles','gestion_marcas','justificaciones',
      'asignacion_horarios','procesar_asistencia','reporte_resumen','reporte_consolidado',
      'acceso_marcador','solicitud_vacaciones'
  )
  AND NOT EXISTS (
        SELECT 1 FROM dbo.WEB_AccessProfileMenu x
        WHERE x.ProfileCode = 'ADMIN' AND x.MenuCode = m.MenuCode
  );

/* Perfiles ya existentes: agregar menús de Asistencia (no quitar los de Planillas) */
INSERT INTO dbo.WEB_AccessProfileMenu (ProfileCode, MenuCode)
SELECT p.ProfileCode, m.MenuCode
FROM dbo.WEB_AccessProfile p
CROSS JOIN dbo.WEB_MenuOption m
WHERE p.Status = 'A'
  AND m.Status = 'A'
  AND m.MenuCode IN (
      'dashboard','maestro_horarios','tipos_justificacion','feriados','configurar_alertas',
      'perfiles_acceso','asignar_perfiles','gestion_marcas','justificaciones',
      'asignacion_horarios','procesar_asistencia','reporte_resumen','reporte_consolidado',
      'acceso_marcador','solicitud_vacaciones'
  )
  AND NOT EXISTS (
        SELECT 1 FROM dbo.WEB_AccessProfileMenu x
        WHERE x.ProfileCode = p.ProfileCode AND x.MenuCode = m.MenuCode
  );

/* Asignar ADMIN a adminquimica si existe y no tiene perfil */
IF EXISTS (SELECT 1 FROM dbo.SY_User WHERE UserID = 'adminquimica')
   AND NOT EXISTS (SELECT 1 FROM dbo.WEB_UserAccessProfile WHERE UserID = 'adminquimica')
BEGIN
    INSERT INTO dbo.WEB_UserAccessProfile (UserID, ProfileCode, XLastUser, XLastDate)
    VALUES ('adminquimica', 'ADMIN', 'SYSTEM', GETDATE());
END;
GO
