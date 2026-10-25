"""Banco de horas / compensación — sobretiempo (crédito) y goce (débito)."""
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


def minutos_a_horas_label(minutos):
    try:
        m = int(minutos or 0)
    except (TypeError, ValueError):
        m = 0
    return round(m / 60.0, 2)


def calc_minutos_rango(hora_inicio, hora_fin):
    """HH:mm o HH:mm:ss → minutos (>=0)."""
    def _parts(s):
        bits = str(s or '').strip().split(':')
        if len(bits) < 2:
            return None
        try:
            return int(bits[0]) * 60 + int(bits[1])
        except ValueError:
            return None
    a = _parts(hora_inicio)
    b = _parts(hora_fin)
    if a is None or b is None:
        return 0
    return max(0, b - a)


def get_resumen_banco_horas(company, person):
    """KPIs: saldo_favor, deudoras, gozadas (en horas)."""
    out = {'saldo_favor_min': 0, 'deuda_min': 0, 'gozadas_min': 0,
           'saldo_favor': 0.0, 'deuda': 0.0, 'gozadas': 0.0}
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                ISNULL(SUM(CASE WHEN TipoMov = 'CREDITO' THEN Minutos ELSE 0 END), 0),
                ISNULL(SUM(CASE WHEN TipoMov = 'DEBITO'  THEN Minutos ELSE 0 END), 0),
                ISNULL(SUM(CASE WHEN TipoMov = 'DEUDA'   THEN Minutos ELSE 0 END), 0)
            FROM dbo.CA_BancoHorasMov
            WHERE Company = ? AND Person = ?
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        row = cursor.fetchone() or (0, 0, 0)
        credito = int(row[0] or 0)
        debito = int(row[1] or 0)
        deuda = int(row[2] or 0)
        saldo = max(0, credito - debito)
        out['saldo_favor_min'] = saldo
        out['deuda_min'] = deuda
        out['gozadas_min'] = debito
        out['saldo_favor'] = minutos_a_horas_label(saldo)
        out['deuda'] = minutos_a_horas_label(deuda)
        out['gozadas'] = minutos_a_horas_label(debito)
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f'Error en get_resumen_banco_horas: {e}')
        return out
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def _next_line(cursor, table, company, person):
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(Line), 0) + 1
        FROM dbo.{table}
        WHERE Company = ? AND Person = ?
        """,
        (company, person),
    )
    return int((cursor.fetchone() or [1])[0] or 1)


def _insert_movimiento(cursor, company, person, tipo_mov, origen, fecha, minutos,
                       ref_tipo, ref_line, motivo, user_id):
    line = _next_line(cursor, 'CA_BancoHorasMov', company, person)
    cursor.execute(
        """
        IF NOT EXISTS (
            SELECT 1 FROM dbo.CA_BancoHorasMov
            WHERE Company = ? AND Person = ? AND RefTipo = ? AND RefLine = ?
        )
        INSERT INTO dbo.CA_BancoHorasMov (
            Company, Person, Line, TipoMov, Origen, FechaEvento, Minutos,
            RefTipo, RefLine, Motivo, registerdate, xlastuser
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, GETDATE(), ?)
        """,
        (
            company, person, ref_tipo, ref_line,
            company, person, line, tipo_mov, origen, fecha, int(minutos),
            ref_tipo, ref_line, (motivo or '')[:500] or None,
            str(user_id or '').strip()[:20],
        ),
    )


# Jornada estándar para convertir días de papeleta a minutos deudores (demo PromPerú).
MINUTOS_JORNADA_DIA = 480  # 8 h


def minutos_desde_papeleta(modo, horas=None, dias=None, hora_inicio=None, hora_fin=None):
    """Convierte una papeleta a minutos para el banco (deuda)."""
    modo_s = str(modo or 'H').strip().upper()[:1]
    if modo_s == 'D':
        try:
            d = int(dias or 0)
        except (TypeError, ValueError):
            d = 0
        return max(0, d * MINUTOS_JORNADA_DIA)
    # Modo horas
    try:
        h = float(horas or 0)
    except (TypeError, ValueError):
        h = 0.0
    if h > 0:
        return max(0, int(round(h * 60)))
    return calc_minutos_rango(hora_inicio, hora_fin)


def abonar_deuda_papeleta_personal(cursor, company, person, papeleta_line, papeleta_row, user_id):
    """
    Si la papeleta es Asuntos Personales (PERSONAL), registra DEUDA en el banco.
    Idempotente por RefTipo=PAPELETA + RefLine.
    Retorna minutos abonados (0 si no aplica).
    """
    tipo = str((papeleta_row or {}).get('TipoCodigo') or '').strip().upper()
    if tipo != 'PERSONAL':
        return 0
    minutos = minutos_desde_papeleta(
        (papeleta_row or {}).get('Modo'),
        horas=(papeleta_row or {}).get('Horas'),
        dias=(papeleta_row or {}).get('Dias'),
        hora_inicio=(papeleta_row or {}).get('HoraInicio'),
        hora_fin=(papeleta_row or {}).get('HoraFin'),
    )
    if minutos <= 0:
        return 0
    fecha = (papeleta_row or {}).get('Fecha') or (papeleta_row or {}).get('FechaInicio')
    motivo = (papeleta_row or {}).get('Motivo') or 'Papeleta asuntos personales'
    _insert_movimiento(
        cursor, company, person, 'DEUDA', 'PAPELETA_PERSONAL',
        fecha, minutos, 'PAPELETA', int(papeleta_line),
        motivo, user_id,
    )
    return minutos



def registrar_sobretiempo(company, person, fecha, hora_inicio, hora_fin, motivo, user_id,
                          drive_file_id=None, local_sustento=None, nombre_sustento=None):
    minutos = calc_minutos_rango(hora_inicio, hora_fin)
    if minutos <= 0:
        return False, None, 'El rango de horas no es válido.'
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        line = _next_line(cursor, 'CA_SobretiempoSolicitud', cia, per)
        comments = None
        if drive_file_id:
            comments = f'SUSTENTO_DRIVE:{str(drive_file_id).strip()}'[:255]
        elif local_sustento:
            comments = f'SUSTENTO_LOCAL:{str(local_sustento).strip()}'[:255]
        cursor.execute(
            """
            INSERT INTO dbo.CA_SobretiempoSolicitud (
                Company, Person, Line, Fecha, HoraInicio, HoraFin, Minutos,
                Motivo, status, Comments, NombreSustento,
                registerdate, xlastuser, xlastdate
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?,
                ?, 'P', ?, ?,
                GETDATE(), ?, CONVERT(varchar(19), GETDATE(), 120)
            )
            """,
            (
                cia, per, line, fecha,
                (hora_inicio or '')[:8], (hora_fin or '')[:8], minutos,
                (motivo or '')[:500] or None, comments,
                (nombre_sustento or '')[:255] or None,
                str(user_id or '').strip()[:20],
            ),
        )
        crear_pasos_flujo_solicitud(cia, per, line, 'SOBRETIEMPO', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_sobretiempo: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, None, str(e)
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def registrar_goce(company, person, fecha, hora_inicio, hora_fin, motivo, user_id):
    minutos = calc_minutos_rango(hora_inicio, hora_fin)
    if minutos <= 0:
        return False, None, 'El rango de horas no es válido.'
    resumen = get_resumen_banco_horas(company, person)
    if minutos > int(resumen.get('saldo_favor_min') or 0):
        return False, None, (
            f"Saldo insuficiente. Disponible: {resumen.get('saldo_favor')} h; "
            f"solicitado: {minutos_a_horas_label(minutos)} h."
        )
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        line = _next_line(cursor, 'CA_GoceCompensacion', cia, per)
        cursor.execute(
            """
            INSERT INTO dbo.CA_GoceCompensacion (
                Company, Person, Line, Fecha, HoraInicio, HoraFin, Minutos,
                Motivo, status, registerdate, xlastuser, xlastdate
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?,
                ?, 'P', GETDATE(), ?, CONVERT(varchar(19), GETDATE(), 120)
            )
            """,
            (
                cia, per, line, fecha,
                (hora_inicio or '')[:8], (hora_fin or '')[:8], minutos,
                (motivo or '')[:500] or None,
                str(user_id or '').strip()[:20],
            ),
        )
        crear_pasos_flujo_solicitud(cia, per, line, 'GOCE_COMP', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_goce: {e}')
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return False, None, str(e)
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def _enrich_flujo(rows, company, person, tipo_wf):
    for r in rows:
        try:
            sid = int(r.get('Id') or r.get('id'))
        except (TypeError, ValueError):
            continue
        cia = r.get('Company') or company
        per = r.get('Person') or person
        if str(r.get('status') or '').upper() == 'P':
            asegurar_pasos_flujo_solicitud(cia, per, sid, tipo_wf)
        pasos = get_pasos_flujo_solicitud(cia, per, sid, tipo_wf)
        r['flujo'] = resumir_estado_flujo_vacaciones(pasos, r.get('status'))
        r['pasos_flujo'] = pasos
        r['tipo_solicitud'] = tipo_wf
    return rows


def get_historial_sobretiempo(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Line AS Id, Company, Person, Fecha, HoraInicio, HoraFin, Minutos,
                   Motivo, status, Comments, NombreSustento, registerdate
            FROM dbo.CA_SobretiempoSolicitud
            WHERE Company = ? AND Person = ?
            ORDER BY registerdate DESC, Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return _enrich_flujo(rows, company, person, 'SOBRETIEMPO')
    except Exception as e:
        print(f'Error en get_historial_sobretiempo: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_historial_goce(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Line AS Id, Company, Person, Fecha, HoraInicio, HoraFin, Minutos,
                   Motivo, status, Comments, registerdate
            FROM dbo.CA_GoceCompensacion
            WHERE Company = ? AND Person = ?
            ORDER BY registerdate DESC, Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return _enrich_flujo(rows, company, person, 'GOCE_COMP')
    except Exception as e:
        print(f'Error en get_historial_goce: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def eliminar_sobretiempo(company, person, line):
    return _eliminar_solicitud(
        'CA_SobretiempoSolicitud', 'SOBRETIEMPO', company, person, line
    )


def eliminar_goce(company, person, line):
    return _eliminar_solicitud(
        'CA_GoceCompensacion', 'GOCE_COMP', company, person, line
    )


def _eliminar_solicitud(table, tipo_wf, company, person, line):
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
                  AND TipoSolicitud = ? AND Estado = 'A'
                """,
                (cia, per, sid, tipo_wf),
            )
            if int((cursor.fetchone() or [0])[0] or 0) > 0:
                return False
            cursor.execute(
                """
                DELETE FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ? AND TipoSolicitud = ?
                """,
                (cia, per, sid, tipo_wf),
            )
        cursor.execute(
            f"""
            DELETE FROM dbo.{table}
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
        print(f'Error en eliminar {table}: {e}')
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


def _cerrar_solicitud(cursor, table, company, person, line, user, status='A', comments=None):
    cia = str(company or '').strip()
    per = str(person or '').strip()
    line_i = int(line)
    user_s = str(user or '').strip()[:20]
    if status == 'A':
        cursor.execute(
            f"""
            UPDATE dbo.{table}
            SET status = 'A', ApprovalUser = ?, ApprovalDate = GETDATE(),
                xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (user_s, user_s, cia, per, line_i),
        )
    else:
        cursor.execute(
            f"""
            UPDATE dbo.{table}
            SET status = 'R', ApprovalUser = ?, ApprovalDate = GETDATE(),
                Comments = ?, xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
            """,
            (user_s, (comments or '')[:255], user_s, cia, per, line_i),
        )
    cursor.execute(
        f"SELECT status FROM dbo.{table} WHERE Company = ? AND Person = ? AND Line = ?",
        (cia, per, line_i),
    )
    row = cursor.fetchone()
    return bool(row) and str(row[0] or '').strip().upper() == status


def _leer_solicitud(cursor, table, company, person, line):
    cursor.execute(
        f"""
        SELECT Fecha, HoraInicio, HoraFin, Minutos, Motivo, status
        FROM dbo.{table}
        WHERE Company = ? AND Person = ? AND Line = ?
        """,
        (company, person, int(line)),
    )
    row = cursor.fetchone()
    if not row:
        return None
    return {
        'Fecha': row[0], 'HoraInicio': row[1], 'HoraFin': row[2],
        'Minutos': int(row[3] or 0), 'Motivo': row[4], 'status': row[5],
    }


def aprobar_paso_compensacion(
    company, person, line, tipo_solicitud, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    tipo = str(tipo_solicitud or '').strip().upper()
    if tipo not in ('SOBRETIEMPO', 'GOCE_COMP'):
        return False, 'Tipo de solicitud no válido.', {}
    table = 'CA_SobretiempoSolicitud' if tipo == 'SOBRETIEMPO' else 'CA_GoceCompensacion'
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud=tipo,
        )
        if not info.get('can_approve'):
            return False, 'No tiene pendiente de aprobación en esta solicitud.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)

        if tipo == 'GOCE_COMP' and info.get('es_nivel_final'):
            sol = _leer_solicitud(cursor, table, cia, per, line_i)
            if not sol or str(sol.get('status') or '').upper() != 'P':
                conn.rollback()
                return False, 'La solicitud ya no está pendiente.', info
            # saldo disponible + minutos de esta solicitud aún no debitados
            cursor.execute(
                """
                SELECT
                    ISNULL(SUM(CASE WHEN TipoMov = 'CREDITO' THEN Minutos ELSE 0 END), 0)
                  - ISNULL(SUM(CASE WHEN TipoMov = 'DEBITO'  THEN Minutos ELSE 0 END), 0)
                FROM dbo.CA_BancoHorasMov
                WHERE Company = ? AND Person = ?
                """,
                (cia, per),
            )
            saldo = int((cursor.fetchone() or [0])[0] or 0)
            if int(sol['Minutos']) > saldo:
                conn.rollback()
                return False, (
                    f'Saldo insuficiente al cerrar goce '
                    f'({minutos_a_horas_label(saldo)} h disponibles).'
                ), info

        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'A', user, observacion,
            tipo_solicitud=tipo,
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info

        if info.get('es_nivel_final'):
            sol = _leer_solicitud(cursor, table, cia, per, line_i)
            if not _cerrar_solicitud(cursor, table, cia, per, line_i, user, status='A'):
                conn.rollback()
                return False, 'No se pudo cerrar la solicitud.', info
            if tipo == 'SOBRETIEMPO':
                _insert_movimiento(
                    cursor, cia, per, 'CREDITO', 'SOBRETIEMPO',
                    sol['Fecha'], sol['Minutos'], 'SOBRETIEMPO', line_i,
                    sol.get('Motivo'), user,
                )
                msg = 'Sobretiempo aprobado. Horas abonadas al banco.'
            else:
                _insert_movimiento(
                    cursor, cia, per, 'DEBITO', 'GOCE',
                    sol['Fecha'], sol['Minutos'], 'GOCE_COMP', line_i,
                    sol.get('Motivo'), user,
                )
                msg = 'Goce compensatorio aprobado. Horas descontadas del saldo.'
            resumen = {
                'codigo': 'APROBADO', 'label': 'Aprobado', 'chip': 'success',
                'detalle': 'Aprobado',
            }
        else:
            cursor.execute(
                f"""
                UPDATE dbo.{table}
                SET xlastuser = ?, xlastdate = CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company = ? AND Person = ? AND Line = ? AND status = 'P'
                """,
                (user, cia, per, line_i),
            )
            total = int((info.get('resumen') or {}).get('total_niveles') or 0)
            siguiente = int(pend.get('Nivel') or 0) + 1
            msg = f"Nivel {pend.get('Nivel')} aprobado. Pasa al siguiente nivel."
            resumen = {
                'codigo': 'EN_APROBACION',
                'label': f'En aprobación ({siguiente}/{total})' if total else 'En aprobación',
                'chip': 'info',
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
        return True, msg, info_out
    except Exception as e:
        print(f'Error en aprobar_paso_compensacion: {e}')
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


def rechazar_paso_compensacion(
    company, person, line, tipo_solicitud, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    tipo = str(tipo_solicitud or '').strip().upper()
    if tipo not in ('SOBRETIEMPO', 'GOCE_COMP'):
        return False, 'Tipo de solicitud no válido.', {}
    table = 'CA_SobretiempoSolicitud' if tipo == 'SOBRETIEMPO' else 'CA_GoceCompensacion'
    motivo = str(observacion or '').strip()
    if not motivo:
        return False, 'El motivo de rechazo es obligatorio.', {}
    conn = None
    try:
        user = str(approval_user or '').strip()[:20]
        info = resolver_accion_flujo(
            company, person, line, person_actor, profilecode,
            menus=menus, unrestricted=unrestricted, web_admin=web_admin,
            approval_userid=user, tipo_solicitud=tipo,
        )
        if not info.get('can_reject'):
            return False, 'No tiene pendiente de rechazo en esta solicitud.', info
        pend = info['paso_pendiente']
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cia = str(company or '').strip()
        per = str(person or '').strip()
        line_i = int(line)
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'R', user, motivo,
            tipo_solicitud=tipo,
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info
        if _wf_tiene_tipo_solicitud(cursor):
            cursor.execute(
                """
                UPDATE dbo.WF_SolicitudPaso
                SET Estado = 'R', UserID = ?, FechaRespuesta = GETDATE(), Observacion = ?
                WHERE Company = ? AND Person = ? AND Line = ?
                  AND TipoSolicitud = ? AND Estado = 'P'
                """,
                (user, f'Cerrado por rechazo en nivel {pend.get("Nivel")}'[:500],
                 cia, per, line_i, tipo),
            )
        if not _cerrar_solicitud(cursor, table, cia, per, line_i, user, status='R', comments=motivo):
            conn.rollback()
            return False, 'No se pudo rechazar la solicitud.', info
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
        return True, 'Solicitud rechazada.', info
    except Exception as e:
        print(f'Error en rechazar_paso_compensacion: {e}')
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
