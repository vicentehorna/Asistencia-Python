"""Papeletas de salida / permisos — Portal Trabajador + flujo WF PAPELETA."""
import os
import re
from pathlib import Path

from database import (
    DatabaseConfig,
    asegurar_pasos_flujo_solicitud,
    get_pasos_flujo_solicitud,
    crear_pasos_flujo_solicitud,
    resumir_estado_flujo_vacaciones,
    resolver_accion_flujo,
    _wf_tablas_listas,
    _wf_tiene_tipo_solicitud,
    _wf_marcar_paso,
)


_RE_SUSTENTO_DRIVE = re.compile(r'SUSTENTO_DRIVE:([A-Za-z0-9_-]+)', re.I)
_RE_SUSTENTO_LOCAL = re.compile(r'SUSTENTO_LOCAL:([^\s|;]+)', re.I)


def carpeta_sustentos_locales(app_root=None):
    """Carpeta local para demo en la misma PC (sin Google Drive)."""
    base = Path(app_root or os.getcwd())
    dest = base / 'uploads' / 'sustentos_papeletas'
    dest.mkdir(parents=True, exist_ok=True)
    return dest


def parse_sustento_comments(comments):
    text = str(comments or '')
    m = _RE_SUSTENTO_DRIVE.search(text)
    if m:
        return {'tipo': 'drive', 'ref': m.group(1)}
    m = _RE_SUSTENTO_LOCAL.search(text)
    if m:
        return {'tipo': 'local', 'ref': m.group(1).strip()}
    return {'tipo': None, 'ref': None}


def drive_file_id_desde_comments(comments):
    info = parse_sustento_comments(comments)
    return info['ref'] if info.get('tipo') == 'drive' else None


def local_sustento_desde_comments(comments):
    info = parse_sustento_comments(comments)
    return info['ref'] if info.get('tipo') == 'local' else None


def tiene_sustento_en_comments(comments):
    return bool(parse_sustento_comments(comments).get('ref'))


def guardar_sustento_local(archivo_stream, nombre_archivo, app_root=None):
    """Guarda PDF en disco local. Retorna nombre de archivo relativo."""
    safe = re.sub(r'[^\w.\-]+', '_', str(nombre_archivo or 'sustento.pdf'))[:120]
    if not safe.lower().endswith('.pdf'):
        safe = f'{safe}.pdf'
    dest_dir = carpeta_sustentos_locales(app_root)
    dest = dest_dir / safe
    if dest.exists():
        stem = dest.stem
        for i in range(1, 50):
            cand = dest_dir / f'{stem}_{i}.pdf'
            if not cand.exists():
                dest = cand
                safe = cand.name
                break
    data = archivo_stream.read() if hasattr(archivo_stream, 'read') else archivo_stream
    dest.write_bytes(data)
    return safe


def obtener_comments_sustento_papeleta(company, person, line):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT TOP 1 Comments, NombreSustento
            FROM dbo.CA_PapeletaSolicitud
            WHERE Company = ? AND Person = ? AND Line = ?
            """,
            (str(company or '').strip(), str(person or '').strip(), int(line)),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row:
            return None, None
        return row[0], row[1]
    except Exception as e:
        print(f'Error en obtener_comments_sustento_papeleta: {e}')
        return None, None
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def obtener_drive_file_id_sustento_papeleta(company, person, line):
    comments, _ = obtener_comments_sustento_papeleta(company, person, line)
    return drive_file_id_desde_comments(comments)


def tipo_requiere_sustento(tipo_codigo):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT TOP 1 RequiereSustento
            FROM dbo.CA_PapeletaTipo
            WHERE Codigo = ? AND Activo = 1
            """,
            (str(tipo_codigo or '').strip().upper(),),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        return bool(row and row[0])
    except Exception:
        return False
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass



def listar_tipos_papeleta():
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Codigo, Nombre, ModoDefault, RequiereSustento, SortOrder
            FROM dbo.CA_PapeletaTipo
            WHERE Activo = 1
            ORDER BY SortOrder, Nombre
            """
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return rows
    except Exception as e:
        print(f'Error en listar_tipos_papeleta: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_historial_papeletas(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                p.Line AS Id, p.Company, p.Person, p.TipoCodigo, t.Nombre AS TipoNombre,
                p.Modo, p.Fecha, p.HoraInicio, p.HoraFin, p.Horas,
                p.FechaInicio, p.FechaFin, p.Dias, p.Motivo, p.status,
                p.Comments, p.NombreSustento, p.registerdate, p.ApprovalDate, p.ApprovalUser
            FROM dbo.CA_PapeletaSolicitud p
            LEFT JOIN dbo.CA_PapeletaTipo t ON t.Codigo = p.TipoCodigo
            WHERE p.Company = ? AND p.Person = ?
            ORDER BY p.registerdate DESC, p.Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        results = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        for r in results:
            try:
                sid = int(r.get('Id'))
            except (TypeError, ValueError):
                continue
            if str(r.get('status') or '').upper() == 'P':
                asegurar_pasos_flujo_solicitud(
                    r.get('Company') or company, r.get('Person') or person, sid, 'PAPELETA'
                )
            pasos = get_pasos_flujo_solicitud(
                r.get('Company') or company, r.get('Person') or person, sid, 'PAPELETA'
            )
            r['flujo'] = resumir_estado_flujo_vacaciones(pasos, r.get('status'))
            r['pasos_flujo'] = pasos
        return results
    except Exception as e:
        print(f'Error en get_historial_papeletas: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def registrar_papeleta(
    company, person, tipo_codigo, modo, motivo, user_id,
    fecha=None, hora_inicio=None, hora_fin=None, horas=None,
    fecha_inicio=None, fecha_fin=None, dias=None,
    drive_file_id=None, local_sustento=None, nombre_sustento=None,
):
    """Inserta papeleta P y crea pasos WF PAPELETA. Retorna (ok, line)."""
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        tipo = str(tipo_codigo or '').strip().upper()
        modo_s = str(modo or 'H').strip().upper()[:1]
        if modo_s not in ('H', 'D'):
            modo_s = 'H'
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT ISNULL(MAX(Line), 0) + 1
            FROM dbo.CA_PapeletaSolicitud
            WHERE Company = ? AND Person = ?
            """,
            (cia, per),
        )
        next_line = int((cursor.fetchone() or [1])[0] or 1)
        comments = None
        if drive_file_id:
            comments = f"SUSTENTO_DRIVE:{str(drive_file_id).strip()}"[:255]
        elif local_sustento:
            comments = f"SUSTENTO_LOCAL:{str(local_sustento).strip()}"[:255]
        cursor.execute(
            """
            INSERT INTO dbo.CA_PapeletaSolicitud (
                Company, Person, Line, TipoCodigo, Modo,
                Fecha, HoraInicio, HoraFin, Horas,
                FechaInicio, FechaFin, Dias,
                Motivo, status, Comments, NombreSustento,
                registerdate, xlastuser, xlastdate
            ) VALUES (
                ?, ?, ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?,
                ?, 'P', ?, ?,
                GETDATE(), ?, CONVERT(varchar(19), GETDATE(), 120)
            )
            """,
            (
                cia, per, next_line, tipo, modo_s,
                fecha, (hora_inicio or '')[:8] or None, (hora_fin or '')[:8] or None, horas,
                fecha_inicio, fecha_fin, dias,
                (motivo or '')[:500] or None, comments, (nombre_sustento or '')[:255] or None,
                str(user_id or '').strip()[:20],
            ),
        )
        crear_pasos_flujo_solicitud(cia, per, next_line, 'PAPELETA', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, next_line
    except Exception as e:
        print(f'Error en registrar_papeleta: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, None
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def eliminar_papeleta(company, person, line):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        sid = int(line)
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        if _wf_tablas_listas(cursor) and _wf_tiene_tipo_solicitud(cursor):
            cursor.execute(
                """
                SELECT COUNT(*) FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ?
                  AND TipoSolicitud = 'PAPELETA' AND Estado = 'A'
                """,
                (cia, per, sid),
            )
            if int((cursor.fetchone() or [0])[0] or 0) > 0:
                return False
            cursor.execute(
                """
                DELETE FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ? AND TipoSolicitud = 'PAPELETA'
                """,
                (cia, per, sid),
            )
        cursor.execute(
            """
            DELETE FROM dbo.CA_PapeletaSolicitud
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (cia, per, sid),
        )
        ok = cursor.rowcount > 0
        conn.commit()
        cursor.close()
        conn.close()
        return ok
    except Exception as e:
        print(f'Error en eliminar_papeleta: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def _cerrar_papeleta(cursor, company, person, line, user, status='A', comments=None):
    cia = str(company or '').strip()
    per = str(person or '').strip()
    line_i = int(line)
    user_s = str(user or '').strip()[:20]
    if status == 'A':
        cursor.execute(
            """
            UPDATE dbo.CA_PapeletaSolicitud
            SET status = 'A', ApprovalUser = ?, ApprovalDate = GETDATE(),
                xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (user_s, user_s, cia, per, line_i),
        )
    else:
        cursor.execute(
            """
            UPDATE dbo.CA_PapeletaSolicitud
            SET status = 'R', ApprovalUser = ?, ApprovalDate = GETDATE(),
                Comments = ?, xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (user_s, (comments or '')[:255], user_s, cia, per, line_i),
        )
    cursor.execute(
        """
        SELECT status FROM dbo.CA_PapeletaSolicitud
        WHERE Company = ? AND Person = ? AND Line = ?
        """,
        (cia, per, line_i),
    )
    row = cursor.fetchone()
    return bool(row) and str(row[0] or '').strip().upper() == status


def aprobar_paso_flujo_papeleta(
    company, person, line, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud='PAPELETA',
        )
        if not info.get('can_approve'):
            return False, 'No tiene pendiente de aprobacion en esta papeleta.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'A', user, observacion,
            tipo_solicitud='PAPELETA',
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info
        if info.get('es_nivel_final'):
            if not _cerrar_papeleta(cursor, cia, per, line_i, user, status='A'):
                conn.rollback()
                return False, 'No se pudo cerrar la papeleta (ya no esta pendiente).', info
            # Asuntos personales → horas deudoras en banco de horas
            cursor.execute(
                """
                SELECT TipoCodigo, Modo, Fecha, HoraInicio, HoraFin, Horas,
                       FechaInicio, FechaFin, Dias, Motivo
                FROM dbo.CA_PapeletaSolicitud
                WHERE Company = ? AND Person = ? AND Line = ?
                """,
                (cia, per, line_i),
            )
            prow = cursor.fetchone()
            deuda_min = 0
            if prow:
                from banco_horas import abonar_deuda_papeleta_personal, minutos_a_horas_label
                papeleta_row = {
                    'TipoCodigo': prow[0], 'Modo': prow[1], 'Fecha': prow[2],
                    'HoraInicio': prow[3], 'HoraFin': prow[4], 'Horas': prow[5],
                    'FechaInicio': prow[6], 'FechaFin': prow[7], 'Dias': prow[8],
                    'Motivo': prow[9],
                }
                deuda_min = abonar_deuda_papeleta_personal(
                    cursor, cia, per, line_i, papeleta_row, user
                )
            if deuda_min > 0:
                msg = (
                    'Papeleta aprobada. Se registraron '
                    f'{minutos_a_horas_label(deuda_min):.2f} h deudoras en el banco de horas.'
                )
            else:
                msg = 'Papeleta aprobada en todos los niveles.'
            resumen = {
                'codigo': 'APROBADO', 'label': 'Aprobado', 'chip': 'success',
                'nivel_actual': info.get('resumen', {}).get('total_niveles'),
                'total_niveles': info.get('resumen', {}).get('total_niveles'),
                'detalle': 'Aprobado',
            }
        else:
            cursor.execute(
                """
                UPDATE dbo.CA_PapeletaSolicitud
                SET xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
                """,
                (user, cia, per, line_i),
            )
            total = int((info.get('resumen') or {}).get('total_niveles') or 0)
            siguiente = int(pend.get('Nivel') or 0) + 1
            msg = (
                f"Nivel {pend.get('Nivel')} aprobado "
                f"({pend.get('Descripcion') or ''}). Pasa al siguiente nivel."
            )
            resumen = {
                'codigo': 'EN_APROBACION',
                'label': f'En aprobacion ({siguiente}/{total})' if total else 'En aprobacion',
                'chip': 'info',
                'nivel_actual': siguiente,
                'total_niveles': total,
                'detalle': f'Nivel {siguiente}/{total}' if total else 'Siguiente nivel',
            }
        conn.commit()
        try:
            cursor.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass
        conn = None
        info_out = dict(info)
        info_out['resumen'] = resumen
        info_out['can_approve'] = False
        info_out['can_reject'] = False
        info_out['paso_pendiente'] = None
        return True, msg, info_out
    except Exception as e:
        print(f'Error en aprobar_paso_flujo_papeleta: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, str(e), {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def rechazar_paso_flujo_papeleta(
    company, person, line, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    motivo = str(observacion or '').strip()
    if not motivo:
        return False, 'El motivo de rechazo es obligatorio.', {}
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud='PAPELETA',
        )
        if not info.get('can_reject'):
            return False, 'No tiene pendiente de rechazo en esta papeleta.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'R', user, motivo,
            tipo_solicitud='PAPELETA',
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info
        if _wf_tiene_tipo_solicitud(cursor):
            cursor.execute(
                """
                UPDATE dbo.WF_SolicitudPaso
                SET Estado = 'R', UserID = ?, FechaRespuesta = GETDATE(), Observacion = ?
                WHERE Company = ? AND Person = ? AND Line = ?
                  AND TipoSolicitud = 'PAPELETA' AND Estado = 'P'
                """,
                (user, f'Cerrado por rechazo en nivel {pend.get("Nivel")}'[:500], cia, per, line_i),
            )
        if not _cerrar_papeleta(cursor, cia, per, line_i, user, status='R', comments=motivo):
            conn.rollback()
            return False, 'No se pudo rechazar la papeleta (ya no esta pendiente).', info
        conn.commit()
        try:
            cursor.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass
        conn = None
        return True, 'Papeleta rechazada.', info
    except Exception as e:
        print(f'Error en rechazar_paso_flujo_papeleta: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, str(e), {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass
