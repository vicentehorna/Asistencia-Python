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
    ('solicitud_vacaciones', 'Solicitud de Vacaciones',   'portal_trabajador', 510, 'solicitud_vacaciones_page', '/solicitud-vacaciones', 'A'),
    ('solicitud_papeletas',  'Solicitud de Papeletas',    'portal_trabajador', 515, 'solicitud_papeletas_page', '/solicitud-papeletas', 'A'),
    ('banco_horas',          'Banco de Horas',            'portal_trabajador', 518, 'banco_horas_page', '/banco-horas', 'A'),
    ('teletrabajo',          'Teletrabajo',               'portal_trabajador', 519, 'teletrabajo_page', '/teletrabajo', 'A'),
    ('consulta_asistencia',  'Consulta de Asistencia',    'portal_trabajador', 525, 'consulta_asistencia_page', '/consulta-asistencia', 'A'),
    ('detalle_vacaciones',   'Detalle de Vacaciones',     'portal_trabajador', 520, 'reporte_vacaciones_detalle_page', '/reporte-vacaciones-detalle', 'A'),
    ('saldo_vacaciones',     'Saldo de Vacaciones',       'portal_trabajador', 530, 'reporte_saldo_vacaciones_page', '/reporte-saldo-vacaciones', 'A'),
    ('aprobar_vacaciones',   'Aprobar Vacaciones',        'aprobaciones',      610, 'reporte_aprobar_vacaciones_page', '/reporte-aprobar-vacaciones', 'A'),
    ('aprobar_papeletas',    'Aprobar Papeletas',         'aprobaciones',      620, 'aprobar_papeletas_page', '/aprobar-papeletas', 'A'),
    ('aprobar_compensaciones','Aprobar Compensaciones',   'aprobaciones',      630, 'aprobar_compensaciones_page', '/aprobar-compensaciones', 'A'),
    ('aprobar_teletrabajo',  'Aprobar Teletrabajo',       'aprobaciones',      640, 'aprobar_teletrabajo_page', '/aprobar-teletrabajo', 'A')
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
      'acceso_marcador','solicitud_vacaciones','solicitud_papeletas','banco_horas','teletrabajo',
      'consulta_asistencia','detalle_vacaciones','saldo_vacaciones',
      'aprobar_vacaciones','aprobar_papeletas','aprobar_compensaciones','aprobar_teletrabajo'
  )
  AND NOT EXISTS (
        SELECT 1 FROM dbo.WEB_AccessProfileMenu x
        WHERE x.ProfileCode = 'ADMIN' AND x.MenuCode = m.MenuCode
  );

/* Perfiles ya existentes (excepto SIMPLE): agregar menús de Asistencia (no quitar Planillas) */
INSERT INTO dbo.WEB_AccessProfileMenu (ProfileCode, MenuCode)
SELECT p.ProfileCode, m.MenuCode
FROM dbo.WEB_AccessProfile p
CROSS JOIN dbo.WEB_MenuOption m
WHERE p.Status = 'A'
  AND p.ProfileCode <> 'SIMPLE'
  AND m.Status = 'A'
  AND m.MenuCode IN (
      'dashboard','maestro_horarios','tipos_justificacion','feriados','configurar_alertas',
      'perfiles_acceso','asignar_perfiles','gestion_marcas','justificaciones',
      'asignacion_horarios','procesar_asistencia','reporte_resumen','reporte_consolidado',
      'acceso_marcador','solicitud_vacaciones','solicitud_papeletas','banco_horas','teletrabajo',
      'consulta_asistencia','detalle_vacaciones','saldo_vacaciones',
      'aprobar_vacaciones','aprobar_papeletas','aprobar_compensaciones','aprobar_teletrabajo'
  )
  AND NOT EXISTS (
        SELECT 1 FROM dbo.WEB_AccessProfileMenu x
        WHERE x.ProfileCode = p.ProfileCode AND x.MenuCode = m.MenuCode
  );

/* SIMPLE: solo Portal Trabajador (solicitud + reportes propios) */
INSERT INTO dbo.WEB_AccessProfileMenu (ProfileCode, MenuCode)
SELECT 'SIMPLE', m.MenuCode
FROM dbo.WEB_MenuOption m
WHERE m.Status = 'A'
  AND m.MenuCode IN (
      'solicitud_vacaciones', 'solicitud_papeletas', 'banco_horas', 'teletrabajo',
      'consulta_asistencia', 'detalle_vacaciones', 'saldo_vacaciones'
  )
  AND EXISTS (SELECT 1 FROM dbo.WEB_AccessProfile WHERE ProfileCode = 'SIMPLE')
  AND NOT EXISTS (
        SELECT 1 FROM dbo.WEB_AccessProfileMenu x
        WHERE x.ProfileCode = 'SIMPLE' AND x.MenuCode = m.MenuCode
  );

/* APROBADOR / JEFEAREA: bandejas de papeletas, compensaciones y teletrabajo */
INSERT INTO dbo.WEB_AccessProfileMenu (ProfileCode, MenuCode)
SELECT p.ProfileCode, m.MenuCode
FROM dbo.WEB_AccessProfile p
CROSS JOIN dbo.WEB_MenuOption m
WHERE p.Status = 'A'
  AND p.ProfileCode IN ('APROBADOR', 'JEFEAREA')
  AND m.Status = 'A'
  AND m.MenuCode IN (
      'aprobar_papeletas', 'solicitud_papeletas',
      'aprobar_compensaciones', 'banco_horas',
      'aprobar_teletrabajo', 'teletrabajo'
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
