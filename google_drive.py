"""
Helpers mínimos de Google Drive para Aprobar Vacaciones (sustento PDF).
Misma lógica que Portal Minero: service account + unidad compartida.
"""
from __future__ import annotations

import io
import json
import logging
import os
import re
from pathlib import Path


def normalizar_folder_id_drive(valor):
    raw = str(valor or '').strip()
    if not raw:
        return None
    m = re.search(r'/folders/([A-Za-z0-9_-]+)', raw)
    if m:
        return m.group(1)
    if re.match(r'^[A-Za-z0-9_-]{10,}$', raw):
        return raw
    return None


def carpeta_sustento_vacaciones_desde_env():
    raw_env = str(os.getenv('GOOGLE_DRIVE_FOLDER_SUSTENTO_VACACIONES') or '').strip()
    folder_id = normalizar_folder_id_drive(raw_env)
    return {
        'folder_id': folder_id,
        'source': 'env:GOOGLE_DRIVE_FOLDER_SUSTENTO_VACACIONES',
        'raw': raw_env,
        'normalized': folder_id,
    }


def nombre_archivo_sustento_vacaciones(dni, periodo):
    dni_s = re.sub(r'[^\w\-]+', '_', str(dni or '').strip())[:40] or 'SIN_DNI'
    per_s = re.sub(r'[^\w\-]+', '_', str(periodo or '').strip())[:20] or 'SIN_PERIODO'
    return f'Sustento_Vacaciones_{dni_s}_{per_s}.pdf'


def nombre_archivo_sustento_papeleta(dni, tipo_codigo, line):
    dni_s = re.sub(r'[^\w\-]+', '_', str(dni or '').strip())[:40] or 'SIN_DNI'
    tipo_s = re.sub(r'[^\w\-]+', '_', str(tipo_codigo or '').strip())[:30] or 'PAPELETA'
    line_s = re.sub(r'[^\w\-]+', '_', str(line or '').strip())[:12] or '0'
    return f'Sustento_Papeleta_{dni_s}_{tipo_s}_{line_s}.pdf'


def _drive_http_timeout_seconds():
    try:
        return max(30, int(os.getenv('GOOGLE_HTTP_TIMEOUT', '180')))
    except (TypeError, ValueError):
        return 180


def _resolver_credenciales_drive(app_root=None):
    root = Path(app_root or os.getcwd())
    for env_key in ('GOOGLE_DRIVE_CREDENTIALS_FILE', 'SERVICE_ACCOUNT_FILE'):
        cfg = str(os.getenv(env_key) or '').strip()
        if not cfg:
            continue
        p = Path(cfg)
        if not p.is_absolute():
            p = root / p
        if p.is_file():
            return str(p)
    for fname in ('google_keys.json',):
        p = root / fname
        if p.is_file():
            return str(p)
    for p in root.glob('*.json'):
        try:
            with p.open('r', encoding='utf-8') as f:
                data = json.load(f)
            if str(data.get('type') or '').strip() == 'service_account':
                return str(p)
        except Exception:
            continue
    return None


def _credentials_drive_service_account(scopes=None, subject=None, app_root=None):
    try:
        from google.oauth2 import service_account
    except Exception as e:
        raise RuntimeError(
            'Faltan dependencias de Google Drive. Instale google-api-python-client y google-auth.'
        ) from e

    scopes = scopes or ['https://www.googleapis.com/auth/drive.readonly']

    for env_name in ('GOOGLE_DRIVE_CREDENTIALS_JSON', 'GOOGLE_SERVICE_ACCOUNT_JSON'):
        raw = str(os.getenv(env_name) or '').strip()
        if not raw:
            continue
        try:
            info = json.loads(raw)
        except json.JSONDecodeError as e:
            raise RuntimeError(
                f'La variable {env_name} no contiene JSON válido.'
            ) from e
        if str(info.get('type') or '').strip() != 'service_account':
            raise RuntimeError(
                f'La variable {env_name} debe ser un JSON de Google con "type": "service_account".'
            )
        creds = service_account.Credentials.from_service_account_info(info, scopes=scopes)
        if subject:
            creds = creds.with_subject(str(subject).strip())
        return creds

    cred_path = _resolver_credenciales_drive(app_root=app_root)
    if not cred_path:
        raise RuntimeError(
            'No hay credenciales de Google Drive. Defina GOOGLE_DRIVE_CREDENTIALS_JSON '
            'o GOOGLE_DRIVE_CREDENTIALS_FILE.'
        )
    creds = service_account.Credentials.from_service_account_file(cred_path, scopes=scopes)
    if subject:
        creds = creds.with_subject(str(subject).strip())
    return creds


def _drive_refresh_credentials_if_needed(creds):
    if not creds:
        return
    try:
        from google.auth.transport.requests import Request as GoogleAuthRequest
    except Exception:
        return
    try:
        if getattr(creds, 'expired', False) or not getattr(creds, 'valid', True):
            creds.refresh(GoogleAuthRequest())
    except Exception:
        logging.debug('Drive: refresh omitido', exc_info=True)


def build_drive_service(scopes=None, subject=None, app_root=None):
    try:
        from googleapiclient.discovery import build
    except Exception as e:
        raise RuntimeError(
            'Faltan dependencias de Google Drive. Instale google-api-python-client y google-auth.'
        ) from e

    creds = _credentials_drive_service_account(scopes, subject=subject, app_root=app_root)
    _drive_refresh_credentials_if_needed(creds)
    timeout_s = _drive_http_timeout_seconds()
    try:
        import httplib2
        from google_auth_httplib2 import AuthorizedHttp

        http = httplib2.Http(timeout=timeout_s)
        authed = AuthorizedHttp(creds, http=http)
        return build('drive', 'v3', http=authed, cache_discovery=False)
    except Exception as e:
        logging.warning('Drive: AuthorizedHttp no disponible (%s); cliente por defecto', e)
        return build('drive', 'v3', credentials=creds, cache_discovery=False)


def _drive_http_error_reason(exc):
    try:
        content = getattr(getattr(exc, 'resp', None), 'reason', None) or ''
        if content:
            return str(content)[:500]
        raw = getattr(exc, 'content', b'') or b''
        if isinstance(raw, bytes):
            raw = raw.decode('utf-8', errors='replace')
        if raw:
            data = json.loads(raw)
            err = data.get('error') or {}
            return str(err.get('message') or err.get('status') or raw)[:500]
    except Exception:
        pass
    return str(exc)


def mensaje_error_drive_para_usuario(exc):
    msg = str(exc or '')
    if 'timeout' in msg.lower() or '10060' in msg:
        return (
            'No se pudo conectar con Google Drive (timeout). '
            'Revise red/firewall o reintente más tarde.'
        )
    return msg[:500] or 'Error al acceder a Google Drive.'


def codigo_error_drive_para_soporte(exc):
    return type(exc).__name__


def descargar_archivo_drive(file_id, app_root=None):
    try:
        from googleapiclient.http import MediaIoBaseDownload
    except Exception as e:
        raise RuntimeError('Falta google-api-python-client para descarga desde Drive.') from e

    service = build_drive_service(app_root=app_root)
    meta = service.files().get(
        fileId=file_id,
        fields='name,mimeType',
        supportsAllDrives=True,
    ).execute()
    req = service.files().get_media(fileId=file_id, supportsAllDrives=True)
    fh = io.BytesIO()
    downloader = MediaIoBaseDownload(fh, req)
    done = False
    while not done:
        _, done = downloader.next_chunk()
    fh.seek(0)
    nombre = str(meta.get('name') or f'{file_id}.pdf')
    mime = str(meta.get('mimeType') or 'application/pdf')
    return fh, nombre, mime


def subir_pdf_sustento_drive(folder_id, nombre_archivo, archivo_stream, app_root=None):
    try:
        from googleapiclient.errors import HttpError
        from googleapiclient.http import MediaIoBaseUpload
    except Exception as e:
        raise RuntimeError('Falta google-api-python-client para subir archivos a Drive.') from e

    parent_id = str(folder_id or '').strip()
    nombre = str(nombre_archivo or 'documento.pdf').strip()
    drive_service = build_drive_service(
        scopes=['https://www.googleapis.com/auth/drive'],
        app_root=app_root,
    )

    try:
        carpeta = drive_service.files().get(
            fileId=parent_id,
            fields='id,name,driveId,mimeType,capabilities',
            supportsAllDrives=True,
        ).execute()
        drive_id_carpeta = str(carpeta.get('driveId') or '').strip()
        if not drive_id_carpeta:
            raise RuntimeError(
                'La carpeta de GOOGLE_DRIVE_FOLDER_SUSTENTO_VACACIONES no está en una '
                f'Unidad compartida (Shared Drive). ID: {parent_id}'
            )
        caps = carpeta.get('capabilities') or {}
        if caps.get('canAddChildren') is False:
            raise RuntimeError(
                'La service account no puede agregar archivos en esa carpeta de Drive.'
            )
    except HttpError as e:
        status = getattr(getattr(e, 'resp', None), 'status', None)
        reason = _drive_http_error_reason(e)
        if status == 404:
            raise RuntimeError(
                f'Carpeta no encontrada (404). Verifique GOOGLE_DRIVE_FOLDER_SUSTENTO_VACACIONES.'
            ) from e
        raise RuntimeError(f'No se puede acceder a la carpeta (HTTP {status}): {reason}') from e

    media = MediaIoBaseUpload(archivo_stream, mimetype='application/pdf', resumable=False)
    file_metadata = {'name': nombre, 'parents': [parent_id]}
    try:
        created = drive_service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id',
            supportsAllDrives=True,
        ).execute()
    except HttpError as e:
        status = getattr(getattr(e, 'resp', None), 'status', None)
        reason = _drive_http_error_reason(e)
        raise RuntimeError(f'Error al subir a Google Drive (HTTP {status}): {reason}') from e

    file_id = str(created.get('id') or '').strip()
    if not file_id:
        raise RuntimeError('Drive no devolvió el identificador del archivo subido.')
    return file_id
