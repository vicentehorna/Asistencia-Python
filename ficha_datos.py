"""Ficha de Datos — solicitudes de contacto y educación con WF 2 niveles."""
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


def _next_line(cursor, table, company, person):
    cursor.execute(
        f"""
        SELECT ISNULL(MAX(Line), 0) + 1 FROM dbo.{table}
        WHERE Company = ? AND Person = ?
        """,
        (company, person),
    )
    return int((cursor.fetchone() or [1])[0] or 1)


def _fetch_sp_dict(cursor):
    if not cursor.description:
        return None
    cols = [str(c[0]).strip().lower() for c in cursor.description]
    row = cursor.fetchone()
    if not row:
        return None
    return {cols[i]: row[i] for i in range(len(cols))}


def obtener_datos_contacto_actuales(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            'EXEC sp_pr_obtener_datosgenerales_trabajador_web @cia=?, @person=?',
            (str(company or '').strip(), str(person or '').strip()),
        )
        d = _fetch_sp_dict(cursor)
        cursor.close()
        conn.close()
        if not d:
            return {}
        return {
            'sectelephone': str(d.get('sectelephone') or '').strip(),
            'email': str(d.get('email') or '').strip(),
            'address': str(d.get('address') or '').strip(),
            'localite': str(d.get('localite') or '').strip(),
            'ubigeo_texto': str(d.get('ubigeo_texto') or '').strip(),
            'name': str(d.get('name') or d.get('nombre') or '').strip(),
        }
    except Exception as e:
        print(f'Error en obtener_datos_contacto_actuales: {e}')
        return {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def obtener_datos_educacion_actuales(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            'EXEC sp_pr_obtener_datoseducacion_trabajador_web @cia=?, @person=?',
            (str(company or '').strip(), str(person or '').strip()),
        )
        d = _fetch_sp_dict(cursor)
        cursor.close()
        conn.close()
        if not d:
            return {}
        return {
            'instructionlevel': str(d.get('instructionlevel') or '').strip(),
            'instructionlevel_desc': str(d.get('instructionlevel_desc') or '').strip(),
            'costcenter1': str(d.get('costcenter1') or '').strip(),
            'institucion_desc': str(d.get('institucion_desc') or '').strip(),
            'costcenter2': str(d.get('costcenter2') or '').strip(),
            'carrera_desc': str(d.get('carrera_desc') or '').strip(),
            'anio_egreso': str(d.get('anio_egreso') or '').strip(),
            'specialty': str(d.get('specialty') or '').strip(),
            'profesionalstudiescentertype': str(d.get('profesionalstudiescentertype') or '').strip(),
            'istrainer': str(d.get('istrainer') or 'N').strip().upper()[:1] or 'N',
            'indicator': str(d.get('indicator') or '').strip(),
        }
    except Exception as e:
        print(f'Error en obtener_datos_educacion_actuales: {e}')
        return {}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def listar_niveles_instruccion():
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute('EXEC sp_pr_selectorinstructionlevel_web @cia=?', ('',))
        except Exception:
            cursor.execute(
                """
                SELECT InstructionLevel AS id, Description AS text
                FROM dbo.PR_InstructionLevel
                ORDER BY Description
                """
            )
        cols = [str(c[0]).strip().lower() for c in (cursor.description or [])]
        out = []
        while True:
            row = cursor.fetchone()
            if row is None:
                break
            rd = {cols[i]: row[i] for i in range(len(cols))} if cols else {}
            oid = rd.get('id') or rd.get('instructionlevel') or rd.get('value')
            txt = rd.get('text') or rd.get('description') or rd.get('label') or oid
            if oid:
                out.append({'id': str(oid).strip(), 'text': str(txt).strip()})
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f'Error en listar_niveles_instruccion: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def listar_instituciones(company):
    conn = None
    try:
        cia = str(company or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT LTRIM(RTRIM(ISNULL(PDT, ''))) AS id,
                   LTRIM(RTRIM(ISNULL(Description, ISNULL(Name, PDT)))) AS text
            FROM dbo.PR_Institution
            WHERE Company = ? AND NULLIF(LTRIM(RTRIM(PDT)), '') IS NOT NULL
            ORDER BY Description
            """,
            (cia,),
        )
        out = [{'id': str(r[0]).strip(), 'text': str(r[1]).strip()} for r in cursor.fetchall() if r[0]]
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f'Error en listar_instituciones: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def listar_carreras(company, institucion_pdt):
    conn = None
    try:
        cia = str(company or '').strip()
        pdt_inst = str(institucion_pdt or '').strip()
        if not pdt_inst:
            return []
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT LTRIM(RTRIM(ISNULL(c.PDT, ''))) AS id,
                   LTRIM(RTRIM(ISNULL(c.Description, ISNULL(c.Name, c.PDT)))) AS text
            FROM dbo.PR_Career c
            INNER JOIN dbo.PR_Institution i
                ON i.Company = c.Company AND i.Institution = c.Institution
            WHERE c.Company = ? AND i.PDT = ?
              AND NULLIF(LTRIM(RTRIM(c.PDT)), '') IS NOT NULL
            ORDER BY c.Description
            """,
            (cia, pdt_inst),
        )
        out = [{'id': str(r[0]).strip(), 'text': str(r[1]).strip()} for r in cursor.fetchall() if r[0]]
        cursor.close()
        conn.close()
        return out
    except Exception as e:
        print(f'Error en listar_carreras: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def registrar_solicitud_contacto(company, person, telefono, email, address, localite, motivo, user_id):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT COUNT(*) FROM dbo.CA_FichaContactoSolicitud
            WHERE Company = ? AND Person = ? AND status = 'P'
            """,
            (cia, per),
        )
        if int((cursor.fetchone() or [0])[0] or 0) > 0:
            return False, None, 'Ya tiene una solicitud de contacto pendiente.'
        line = _next_line(cursor, 'CA_FichaContactoSolicitud', cia, per)
        cursor.execute(
            """
            INSERT INTO dbo.CA_FichaContactoSolicitud (
                Company, Person, Line, SecTelephone, Email, Address, Localite, Motivo,
                status, registerdate, xlastuser, xlastdate
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'P', GETDATE(), ?, CONVERT(varchar(19), GETDATE(), 120))
            """,
            (
                cia, per, line,
                (telefono or '')[:15] or None,
                (email or '')[:255] or None,
                (address or '')[:255] or None,
                (localite or '')[:20] or None,
                (motivo or '')[:500] or None,
                str(user_id or '').strip()[:20],
            ),
        )
        crear_pasos_flujo_solicitud(cia, per, line, 'FICHA_CONTACTO', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_solicitud_contacto: {e}')
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


def registrar_solicitud_educacion(company, person, datos, motivo, user_id):
    conn = None
    try:
        cia = str(company or '').strip()
        per = str(person or '').strip()
        d = datos or {}
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT COUNT(*) FROM dbo.CA_FichaEducacionSolicitud
            WHERE Company = ? AND Person = ? AND status = 'P'
            """,
            (cia, per),
        )
        if int((cursor.fetchone() or [0])[0] or 0) > 0:
            return False, None, 'Ya tiene una solicitud de educación pendiente.'
        line = _next_line(cursor, 'CA_FichaEducacionSolicitud', cia, per)
        cursor.execute(
            """
            INSERT INTO dbo.CA_FichaEducacionSolicitud (
                Company, Person, Line, InstructionLevel, CostCenter1, CostCenter2,
                AnioEgreso, Specialty, ProfesionalStudiesCenterType, IsTrainer, Indicator,
                Motivo, status, registerdate, xlastuser, xlastdate
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'P', GETDATE(), ?,
                      CONVERT(varchar(19), GETDATE(), 120))
            """,
            (
                cia, per, line,
                (d.get('instructionlevel') or '')[:20] or None,
                (d.get('costcenter1') or '')[:20] or None,
                (d.get('costcenter2') or '')[:20] or None,
                (d.get('anio_egreso') or '')[:10] or None,
                (d.get('specialty') or '')[:100] or None,
                (d.get('profesionalstudiescentertype') or '')[:1] or None,
                (d.get('istrainer') or 'N')[:1] or 'N',
                (d.get('indicator') or '')[:1] or None,
                (motivo or '')[:500] or None,
                str(user_id or '').strip()[:20],
            ),
        )
        crear_pasos_flujo_solicitud(cia, per, line, 'FICHA_EDUCACION', cursor=cursor)
        conn.commit()
        cursor.close()
        conn.close()
        return True, line, None
    except Exception as e:
        print(f'Error en registrar_solicitud_educacion: {e}')
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


def _enrich_historial(rows, company, person, tipo_wf):
    for r in rows:
        try:
            sid = int(r.get('Id'))
        except (TypeError, ValueError):
            continue
        if str(r.get('status') or '').upper() == 'P':
            asegurar_pasos_flujo_solicitud(company, person, sid, tipo_wf)
        pasos = get_pasos_flujo_solicitud(company, person, sid, tipo_wf)
        r['flujo'] = resumir_estado_flujo_vacaciones(pasos, r.get('status'))
        r['pasos_flujo'] = pasos
        r['tipo_solicitud'] = tipo_wf
    return rows


def get_historial_contacto(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Line AS Id, SecTelephone, Email, Address, Localite, Motivo, status, registerdate
            FROM dbo.CA_FichaContactoSolicitud
            WHERE Company = ? AND Person = ?
            ORDER BY registerdate DESC, Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return _enrich_historial(rows, company, person, 'FICHA_CONTACTO')
    except Exception as e:
        print(f'Error en get_historial_contacto: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def get_historial_educacion(company, person):
    conn = None
    try:
        conn = DatabaseConfig.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT Line AS Id, InstructionLevel, CostCenter1, CostCenter2, AnioEgreso,
                   Specialty, ProfesionalStudiesCenterType, IsTrainer, Indicator,
                   Motivo, status, registerdate
            FROM dbo.CA_FichaEducacionSolicitud
            WHERE Company = ? AND Person = ?
            ORDER BY registerdate DESC, Line DESC
            """,
            (str(company or '').strip(), str(person or '').strip()),
        )
        cols = [c[0] for c in cursor.description]
        rows = [dict(zip(cols, r)) for r in cursor.fetchall()]
        cursor.close()
        conn.close()
        return _enrich_historial(rows, company, person, 'FICHA_EDUCACION')
    except Exception as e:
        print(f'Error en get_historial_educacion: {e}')
        return []
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def eliminar_solicitud_ficha(company, person, line, tipo_solicitud):
    tipo = str(tipo_solicitud or '').strip().upper()
    table = (
        'CA_FichaContactoSolicitud' if tipo == 'FICHA_CONTACTO'
        else 'CA_FichaEducacionSolicitud' if tipo == 'FICHA_EDUCACION'
        else None
    )
    if not table:
        return False
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
                (cia, per, sid, tipo),
            )
            if int((cursor.fetchone() or [0])[0] or 0) > 0:
                return False
            cursor.execute(
                """
                DELETE FROM dbo.WF_SolicitudPaso
                WHERE Company = ? AND Person = ? AND Line = ? AND TipoSolicitud = ?
                """,
                (cia, per, sid, tipo),
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
        print(f'Error en eliminar_solicitud_ficha: {e}')
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


def _aplicar_contacto_a_persona(cursor, company, person, sol, user_id):
    """Lee ficha actual, aplica teléfono/email/dirección/localite y actualiza vía SP."""
    cursor.execute(
        'EXEC sp_pr_obtener_datosgenerales_trabajador_web @cia=?, @person=?',
        (company, person),
    )
    actual = _fetch_sp_dict(cursor)
    if not actual:
        raise RuntimeError('No se pudo leer la ficha actual del trabajador.')
    # Consumir resultsets extra si los hay
    while cursor.nextset():
        pass

    birth = actual.get('birthdate')
    if birth is not None and hasattr(birth, 'strftime'):
        birth_s = birth.strftime('%Y-%m-%d')
    else:
        birth_s = str(birth or '').strip()[:10] or None

    cursor.execute(
        """
        EXEC sp_pr_actualizar_datosgenerales_trabajador_web
            @cia=?, @person=?, @name1=?, @name2=?, @lastname1=?, @lastname2=?,
            @birthdate=?, @sex=?, @sectelephone=?, @email=?, @address=?, @nacionalidad=?,
            @localite=?, @employeedocumenttype=?, @documentnumber=?, @replicationunit=?,
            @userid=?, @xlastuser=?
        """,
        (
            company, person,
            str(actual.get('name1') or '').strip(),
            str(actual.get('name2') or '').strip() or None,
            str(actual.get('lastname1') or '').strip(),
            str(actual.get('lastname2') or '').strip() or None,
            birth_s,
            str(actual.get('sex') or '').strip()[:1],
            (sol.get('SecTelephone') if sol.get('SecTelephone') is not None else actual.get('sectelephone')),
            (sol.get('Email') if sol.get('Email') is not None else actual.get('email')),
            (sol.get('Address') if sol.get('Address') is not None else actual.get('address')),
            str(actual.get('nacionalidad') or '').strip() or None,
            (sol.get('Localite') if sol.get('Localite') is not None else actual.get('localite')),
            str(actual.get('employeedocumenttype') or '').strip(),
            str(actual.get('documentnumber') or '').strip(),
            str(actual.get('replicationunit') or '').strip(),
            str(actual.get('userid') or '').strip() or None,
            str(user_id or '').strip()[:20] or None,
        ),
    )
    while cursor.nextset():
        pass


def _aplicar_educacion_a_persona(cursor, company, person, sol, user_id):
    cursor.execute(
        """
        EXEC sp_pr_actualizar_datoseducacion_trabajador_web
            @cia=?, @person=?, @instructionlevel=?, @costcenter1=?, @costcenter2=?,
            @anio_egreso=?, @specialty=?, @profesionalstudiescentertype=?,
            @istrainer=?, @indicator=?, @xlastuser=?
        """,
        (
            company, person,
            sol.get('InstructionLevel'),
            sol.get('CostCenter1'),
            sol.get('CostCenter2'),
            sol.get('AnioEgreso'),
            sol.get('Specialty'),
            sol.get('ProfesionalStudiesCenterType'),
            sol.get('IsTrainer') or 'N',
            sol.get('Indicator'),
            str(user_id or '').strip()[:20] or None,
        ),
    )
    while cursor.nextset():
        pass


def aprobar_paso_ficha(
    company, person, line, tipo_solicitud, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    tipo = str(tipo_solicitud or '').strip().upper()
    if tipo not in ('FICHA_CONTACTO', 'FICHA_EDUCACION'):
        return False, 'Tipo de solicitud no válido.', {}
    table = (
        'CA_FichaContactoSolicitud' if tipo == 'FICHA_CONTACTO'
        else 'CA_FichaEducacionSolicitud'
    )
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
        if not _wf_marcar_paso(
            cursor, cia, per, line_i, pend['Nivel'], 'A', user, observacion,
            tipo_solicitud=tipo,
        ):
            conn.rollback()
            return False, 'El paso ya fue resuelto por otro usuario.', info

        if info.get('es_nivel_final'):
            cursor.execute(
                f"SELECT * FROM dbo.{table} WHERE Company=? AND Person=? AND Line=?",
                (cia, per, line_i),
            )
            cols = [c[0] for c in cursor.description]
            row = cursor.fetchone()
            if not row:
                conn.rollback()
                return False, 'Solicitud no encontrada.', info
            sol = dict(zip(cols, row))
            if str(sol.get('status') or '').upper() != 'P':
                conn.rollback()
                return False, 'La solicitud ya no está pendiente.', info
            if tipo == 'FICHA_CONTACTO':
                _aplicar_contacto_a_persona(cursor, cia, per, sol, user)
                msg = 'Contacto actualizado en la ficha del trabajador.'
            else:
                _aplicar_educacion_a_persona(cursor, cia, per, sol, user)
                msg = 'Educación actualizada en la ficha del trabajador.'
            cursor.execute(
                f"""
                UPDATE dbo.{table}
                SET status='A', ApprovalUser=?, ApprovalDate=GETDATE(),
                    xlastuser=?, xlastdate=CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company=? AND Person=? AND Line=? AND status='P'
                """,
                (user, user, cia, per, line_i),
            )
            resumen = {'codigo': 'APROBADO', 'label': 'Aprobado', 'chip': 'success', 'detalle': 'Aprobado'}
        else:
            cursor.execute(
                f"""
                UPDATE dbo.{table}
                SET xlastuser=?, xlastdate=CONVERT(varchar(19), GETDATE(), 120)
                WHERE Company=? AND Person=? AND Line=? AND status='P'
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
        print(f'Error en aprobar_paso_ficha: {e}')
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


def rechazar_paso_ficha(
    company, person, line, tipo_solicitud, approval_user, person_actor,
    profilecode=None, menus=None, unrestricted=False, web_admin=False,
    observacion=None,
):
    tipo = str(tipo_solicitud or '').strip().upper()
    if tipo not in ('FICHA_CONTACTO', 'FICHA_EDUCACION'):
        return False, 'Tipo de solicitud no válido.', {}
    table = (
        'CA_FichaContactoSolicitud' if tipo == 'FICHA_CONTACTO'
        else 'CA_FichaEducacionSolicitud'
    )
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
                SET Estado='R', UserID=?, FechaRespuesta=GETDATE(), Observacion=?
                WHERE Company=? AND Person=? AND Line=? AND TipoSolicitud=? AND Estado='P'
                """,
                (user, f'Cerrado por rechazo en nivel {pend.get("Nivel")}'[:500],
                 cia, per, line_i, tipo),
            )
        cursor.execute(
            f"""
            UPDATE dbo.{table}
            SET status='R', ApprovalUser=?, ApprovalDate=GETDATE(),
                Comments=?, xlastuser=?, xlastdate=CONVERT(varchar(19), GETDATE(), 120)
            WHERE Company=? AND Person=? AND Line=? AND status='P'
            """,
            (user, motivo[:255], user, cia, per, line_i),
        )
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
        return True, 'Solicitud de ficha rechazada.', info
    except Exception as e:
        print(f'Error en rechazar_paso_ficha: {e}')
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
