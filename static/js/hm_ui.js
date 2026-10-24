/**
 * Mensajes y confirmaciones integrados con Bootstrap (Planillas HM).
 * Reemplaza alert() / confirm() nativos del navegador.
 */
(function (global) {
    'use strict';

    const TOAST_AUTOHIDE_MS = 6000;
    const BANNER_DEFAULT_MS = 6000;

    let confirmModalEl = null;
    let confirmModalInstance = null;
    let confirmResolve = null;
    let confirmOkHandler = null;
    let confirmCancelHandler = null;
    let confirmHiddenHandler = null;

    function escHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function ensureToastContainer() {
        let container = document.getElementById('hmUiToastContainer');
        if (container) return container;
        container = document.createElement('div');
        container.id = 'hmUiToastContainer';
        container.className = 'hm-ui-toast-container';
        container.setAttribute('aria-live', 'polite');
        container.setAttribute('aria-atomic', 'true');
        document.body.appendChild(container);
        return container;
    }

    function toastIconClass(tipo) {
        const map = {
            success: 'bi-check-circle-fill text-success',
            danger: 'bi-exclamation-octagon-fill text-danger',
            error: 'bi-exclamation-octagon-fill text-danger',
            warning: 'bi-exclamation-triangle-fill text-warning',
            info: 'bi-info-circle-fill text-primary',
        };
        return map[String(tipo || 'info').toLowerCase()] || map.info;
    }

    function toastBgClass(tipo) {
        const t = String(tipo || 'info').toLowerCase();
        if (t === 'error') return 'text-bg-danger';
        if (t === 'success') return 'text-bg-success';
        if (t === 'warning') return 'text-bg-warning';
        if (t === 'danger') return 'text-bg-danger';
        return 'text-bg-primary';
    }

    function toast(mensaje, tipo, opts) {
        const options = opts || {};
        const texto = String(mensaje || '').trim();
        if (!texto) return;

        const container = ensureToastContainer();
        const toastId = `hmUiToast_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        const delay = Number(options.delay) > 0 ? Number(options.delay) : TOAST_AUTOHIDE_MS;
        const useHeaderBg = options.headerBg !== false;
        const tipoNorm = String(tipo || 'info').toLowerCase();

        const toastEl = document.createElement('div');
        toastEl.id = toastId;
        toastEl.className = 'toast hm-ui-toast';
        toastEl.setAttribute('role', 'alert');
        toastEl.setAttribute('aria-live', 'assertive');
        toastEl.setAttribute('aria-atomic', 'true');
        toastEl.innerHTML = useHeaderBg
            ? `
                <div class="toast-header ${toastBgClass(tipoNorm)}">
                    <i class="bi ${toastIconClass(tipoNorm)} me-2" aria-hidden="true"></i>
                    <strong class="me-auto">${escHtml(options.titulo || tituloPorTipo(tipoNorm))}</strong>
                    <button type="button" class="btn-close ${tipoNorm === 'warning' ? '' : 'btn-close-white'}" data-bs-dismiss="toast" aria-label="Cerrar"></button>
                </div>
                <div class="toast-body">${escHtml(texto)}</div>
            `
            : `
                <div class="toast-body d-flex align-items-start gap-2">
                    <i class="bi ${toastIconClass(tipoNorm)} mt-1" aria-hidden="true"></i>
                    <div class="flex-grow-1">${escHtml(texto)}</div>
                    <button type="button" class="btn-close ms-2" data-bs-dismiss="toast" aria-label="Cerrar"></button>
                </div>
            `;

        container.appendChild(toastEl);
        const instance = bootstrap.Toast.getOrCreateInstance(toastEl, { delay, autohide: true });
        toastEl.addEventListener('hidden.bs.toast', () => toastEl.remove());
        instance.show();
    }

    function tituloPorTipo(tipo) {
        const map = {
            success: 'Correcto',
            danger: 'Error',
            error: 'Error',
            warning: 'Atención',
            info: 'Información',
        };
        return map[String(tipo || 'info').toLowerCase()] || 'Información';
    }

    function ensureConfirmModal() {
        if (confirmModalEl) return confirmModalEl;

        const wrapper = document.createElement('div');
        wrapper.innerHTML = `
            <div class="modal fade" id="hmUiConfirmModal" tabindex="-1" aria-labelledby="hmUiConfirmModalLabel" aria-hidden="true">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content shadow">
                        <div class="modal-header py-2">
                            <h5 class="modal-title fw-bold d-flex align-items-center gap-2" id="hmUiConfirmModalLabel">
                                <i class="bi bi-question-circle text-primary" id="hmUiConfirmIcon" aria-hidden="true"></i>
                                <span id="hmUiConfirmTitle">Confirmar</span>
                            </h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Cerrar"></button>
                        </div>
                        <div class="modal-body py-3" id="hmUiConfirmBody"></div>
                        <div class="modal-footer py-2">
                            <button type="button" class="btn btn-outline-secondary btn-sm px-3" id="hmUiConfirmCancel">Cancelar</button>
                            <button type="button" class="btn btn-primary btn-sm px-3" id="hmUiConfirmOk">Aceptar</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        confirmModalEl = wrapper.firstElementChild;
        document.body.appendChild(confirmModalEl);
        confirmModalInstance = bootstrap.Modal.getOrCreateInstance(confirmModalEl, {
            backdrop: 'static',
            keyboard: true,
        });
        return confirmModalEl;
    }

    function cleanupConfirmHandlers() {
        const btnOk = document.getElementById('hmUiConfirmOk');
        const btnCancel = document.getElementById('hmUiConfirmCancel');
        if (confirmOkHandler && btnOk) btnOk.removeEventListener('click', confirmOkHandler);
        if (confirmCancelHandler && btnCancel) btnCancel.removeEventListener('click', confirmCancelHandler);
        if (confirmHiddenHandler && confirmModalEl) {
            confirmModalEl.removeEventListener('hidden.bs.modal', confirmHiddenHandler);
        }
        confirmOkHandler = null;
        confirmCancelHandler = null;
        confirmHiddenHandler = null;
        confirmResolve = null;
    }

    function confirmar(opts) {
        const options = opts || {};
        const titulo = String(options.titulo || options.title || 'Confirmar').trim();
        const mensaje = String(options.mensaje || options.message || '').trim();
        const textoOk = String(options.textoOk || options.confirmText || 'Aceptar').trim();
        const textoCancelar = String(options.textoCancelar || options.cancelText || 'Cancelar').trim();
        const variant = String(options.variant || options.tipo || 'primary').trim().toLowerCase();

        ensureConfirmModal();

        const titleEl = document.getElementById('hmUiConfirmTitle');
        const bodyEl = document.getElementById('hmUiConfirmBody');
        const btnOk = document.getElementById('hmUiConfirmOk');
        const btnCancel = document.getElementById('hmUiConfirmCancel');
        const iconEl = document.getElementById('hmUiConfirmIcon');

        if (titleEl) titleEl.textContent = titulo;
        if (bodyEl) {
            bodyEl.innerHTML = mensaje
                ? `<p class="mb-0">${escHtml(mensaje).replace(/\n/g, '<br>')}</p>`
                : '';
        }
        if (btnOk) {
            btnOk.textContent = textoOk;
            btnOk.className = `btn btn-sm px-3 ${variant === 'danger' ? 'btn-danger' : 'btn-primary'}`;
        }
        if (btnCancel) btnCancel.textContent = textoCancelar;
        if (iconEl) {
            iconEl.className = variant === 'danger'
                ? 'bi bi-exclamation-triangle-fill text-danger'
                : 'bi bi-question-circle text-primary';
        }

        cleanupConfirmHandlers();

        return new Promise((resolve) => {
            let settled = false;
            const finish = (value) => {
                if (settled) return;
                settled = true;
                cleanupConfirmHandlers();
                resolve(!!value);
            };

            confirmResolve = finish;
            confirmOkHandler = () => {
                confirmModalInstance.hide();
                finish(true);
            };
            confirmCancelHandler = () => {
                confirmModalInstance.hide();
                finish(false);
            };
            confirmHiddenHandler = () => {
                if (!settled) finish(false);
            };

            btnOk.addEventListener('click', confirmOkHandler);
            btnCancel.addEventListener('click', confirmCancelHandler);
            confirmModalEl.addEventListener('hidden.bs.modal', confirmHiddenHandler, { once: false });

            confirmModalInstance.show();
        });
    }

    const bannerTimers = new WeakMap();

    function bannerClassForTipo(tipo) {
        const t = String(tipo || 'success').toLowerCase();
        if (t === 'danger' || t === 'error') return 'hm-ui-banner-danger';
        if (t === 'warning') return 'hm-ui-banner-warning';
        if (t === 'info') return 'hm-ui-banner-info';
        return 'hm-ui-banner-success';
    }

    function showFormBanner(element, mensaje, tipo, opts) {
        if (!element) return;
        const options = opts || {};
        const texto = String(mensaje || '').trim();
        if (!texto) {
            hideFormBanner(element);
            return;
        }

        const prevTimer = bannerTimers.get(element);
        if (prevTimer) clearTimeout(prevTimer);

        element.textContent = texto;
        element.classList.remove('d-none', 'hm-ui-banner-success', 'hm-ui-banner-danger', 'hm-ui-banner-warning', 'hm-ui-banner-info');
        element.classList.add('hm-ui-form-banner', bannerClassForTipo(tipo));
        element.setAttribute('role', 'status');
        element.setAttribute('aria-live', 'polite');

        const delay = Number(options.delay) > 0 ? Number(options.delay) : BANNER_DEFAULT_MS;
        if (options.autoHide !== false) {
            const timer = setTimeout(() => hideFormBanner(element), delay);
            bannerTimers.set(element, timer);
        }

        if (options.scrollIntoView) {
            element.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
    }

    function hideFormBanner(element) {
        if (!element) return;
        const prevTimer = bannerTimers.get(element);
        if (prevTimer) {
            clearTimeout(prevTimer);
            bannerTimers.delete(element);
        }
        element.textContent = '';
        element.classList.add('d-none');
        element.classList.remove(
            'hm-ui-form-banner',
            'hm-ui-banner-success',
            'hm-ui-banner-danger',
            'hm-ui-banner-warning',
            'hm-ui-banner-info'
        );
    }

    function exito(mensaje, opts) {
        toast(mensaje, 'success', opts);
    }

    function error(mensaje, opts) {
        toast(mensaje, 'danger', opts);
    }

    function advertencia(mensaje, opts) {
        toast(mensaje, 'warning', opts);
    }

    function info(mensaje, opts) {
        toast(mensaje, 'info', opts);
    }

    global.HmUi = {
        toast,
        exito,
        error,
        advertencia,
        info,
        confirmar,
        showFormBanner,
        hideFormBanner,
    };
}(typeof window !== 'undefined' ? window : this));
