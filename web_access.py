"""
Permisos de acceso web (perfiles de menú) — mismo modelo que Planillas.
Migración suave: sin asignación / sin tablas → unrestricted (ve todo).
"""
from __future__ import annotations

import logging
from typing import Optional

# endpoint Flask -> menu_code
ENDPOINT_MENU_MAP = {
    'dashboard': 'dashboard',
    'maestro_horarios': 'maestro_horarios',
    'tipos_justificacion': 'tipos_justificacion',
    'feriados_page': 'feriados',
    'configurar_alertas': 'configurar_alertas',
    'perfiles_acceso_page': 'perfiles_acceso',
    'asignar_perfiles_page': 'asignar_perfiles',
    'gestion_marcas': 'gestion_marcas',
    'justificaciones': 'justificaciones',
    'justificaciones_persona': 'justificaciones',
    'asignacion_horarios': 'asignacion_horarios',
    'procesar_asistencia': 'procesar_asistencia',
    'reporte_resumen': 'reporte_resumen',
    'reporte_consolidado': 'reporte_consolidado',
    'acceso_marcador': 'acceso_marcador',
    'solicitud_vacaciones_page': 'solicitud_vacaciones',
    'api_solicitud_vacaciones_ejercicio': 'solicitud_vacaciones',
}

# Prefijos de API / path -> menu_code (el más específico gana por longitud)
PATH_PREFIX_MENU_MAP = {
    '/api/perfiles-acceso/usuarios': 'asignar_perfiles',
    '/api/perfiles-acceso': 'perfiles_acceso',
    '/perfiles-acceso': 'perfiles_acceso',
    '/asignar-perfiles': 'asignar_perfiles',
    '/api/horarios': 'maestro_horarios',
    '/maestro-horarios': 'maestro_horarios',
    '/api/tipos-justificacion': 'tipos_justificacion',
    '/tipos-justificacion': 'tipos_justificacion',
    '/api/feriados': 'feriados',
    '/feriados': 'feriados',
    '/api/alertas': 'configurar_alertas',
    '/configurar-alertas': 'configurar_alertas',
    '/api/marcas': 'gestion_marcas',
    '/gestion-marcas': 'gestion_marcas',
    '/api/justificaciones_persona': 'justificaciones',
    '/justificaciones-persona': 'justificaciones',
    '/justificaciones': 'justificaciones',
    '/api/asignacion-horarios': 'asignacion_horarios',
    '/asignacion-horarios': 'asignacion_horarios',
    '/api/procesar-asistencia': 'procesar_asistencia',
    '/procesar-asistencia': 'procesar_asistencia',
    '/reporte-resumen': 'reporte_resumen',
    '/reporte-consolidado': 'reporte_consolidado',
    '/api/seguridad/acceso-marcador': 'acceso_marcador',
    '/seguridad/acceso-marcador': 'acceso_marcador',
    '/api/solicitud-vacaciones': 'solicitud_vacaciones',
    '/solicitud-vacaciones': 'solicitud_vacaciones',
}

# Catálogo de menús de Asistencia (hm_quimica también tiene menús de Planillas).
ASISTENCIA_MENU_CODES = frozenset(ENDPOINT_MENU_MAP.values()) | frozenset({'solicitud_vacaciones'})

ALWAYS_ALLOWED_ENDPOINTS = {
    None,
    'static',
    'login',
    'login_post',
    'logout',
    'change_password_route',
}


def default_access_state() -> dict:
    return {
        'unrestricted': True,
        'web_admin': False,
        'profilecode': None,
        'menus': [],
    }


def load_user_web_access(userid: str, get_connection) -> dict:
    """
    Carga permisos desde SP. Si falla (tabla/SP ausente en otras BD) → unrestricted.
    """
    state = default_access_state()
    userid = (userid or '').strip()
    if not userid:
        return state

    conn = None
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_web_obtener_menus_usuario_web @userid=?",
            (userid,),
        )

        cols1 = [str(c[0]).lower() for c in (cursor.description or [])]
        row1 = cursor.fetchone()
        flags = {}
        if row1 and cols1:
            flags = {cols1[i]: row1[i] for i in range(len(cols1))}

        menus: list[str] = []
        if cursor.nextset():
            cols2 = [str(c[0]).lower() for c in (cursor.description or [])]
            while True:
                row = cursor.fetchone()
                if row is None:
                    break
                rd = {cols2[i]: row[i] for i in range(len(cols2))} if cols2 else {}
                code = str(rd.get('menucode') or '').strip()
                if code:
                    menus.append(code)

        unrestricted = int(flags.get('unrestricted') or 0) == 1
        web_admin = int(flags.get('web_admin') or 0) == 1
        profilecode = flags.get('profilecode')
        profilecode = str(profilecode).strip() if profilecode else None

        return {
            'unrestricted': unrestricted,
            'web_admin': web_admin,
            'profilecode': profilecode,
            'menus': menus,
        }
    except Exception:
        logging.exception("load_user_web_access userid=%s", userid)
        return default_access_state()
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def apply_access_to_session(session_obj, state: dict) -> None:
    session_obj['web_access_unrestricted'] = bool(state.get('unrestricted'))
    session_obj['web_admin'] = bool(state.get('web_admin'))
    session_obj['web_profilecode'] = state.get('profilecode')
    session_obj['web_menus'] = list(state.get('menus') or [])


def session_can_menu(session_obj, menu_code: str) -> bool:
    if bool(session_obj.get('web_access_unrestricted')):
        return True
    if bool(session_obj.get('web_admin')):
        return True
    code = (menu_code or '').strip()
    if not code:
        return True
    menus = session_obj.get('web_menus') or []
    return code in menus


def resolve_menu_for_request(endpoint: Optional[str], path: str) -> Optional[str]:
    """Devuelve menu_code requerido o None si no aplica enforcement."""
    if endpoint in ALWAYS_ALLOWED_ENDPOINTS:
        return None
    if endpoint and endpoint in ENDPOINT_MENU_MAP:
        return ENDPOINT_MENU_MAP[endpoint]

    path = path or ''
    if path.startswith('/api/selectores'):
        return None

    best = None
    best_len = -1
    for prefix, code in PATH_PREFIX_MENU_MAP.items():
        if path.startswith(prefix) and len(prefix) > best_len:
            best = code
            best_len = len(prefix)
    return best


def first_allowed_endpoint(session_obj) -> str:
    """Primera pantalla permitida para redirect."""
    if session_can_menu(session_obj, 'dashboard'):
        return 'dashboard'
    preferred = [
        ('maestro_horarios', 'maestro_horarios'),
        ('gestion_marcas', 'gestion_marcas'),
        ('reporte_resumen', 'reporte_resumen'),
        ('perfiles_acceso', 'perfiles_acceso_page'),
        ('asignar_perfiles', 'asignar_perfiles_page'),
    ]
    for code, ep in preferred:
        if session_can_menu(session_obj, code):
            return ep
    menus = session_obj.get('web_menus') or []
    for ep, code in ENDPOINT_MENU_MAP.items():
        if code in menus:
            return ep
    return 'dashboard'
