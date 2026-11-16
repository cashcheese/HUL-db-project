document.addEventListener('DOMContentLoaded', () => {
    
    // --- Global Elements ---
    const usernameSpan = document.getElementById('username');
    const roleSpan = document.getElementById('role');
    const logoutBtn = document.getElementById('logout-btn');
    const refreshBtn = document.getElementById('refresh-btn');
    
    // KPI Cards
    const statPendingOrders = document.getElementById('stat-pending-orders');
    const statOutstandingBalance = document.getElementById('stat-outstanding-balance');
    const adminOnlyCard = document.getElementById('admin-only-card');

    // Tab Buttons & Content
    const tabButtons = document.querySelectorAll('.tab-btn');
    const tabContents = document.querySelectorAll('.tab-content');

    // Tab 1: Order Triage
    const pendingOrdersTbody = document.getElementById('pending-orders-tbody');

    // Tab 2: Inventory
    const inventoryTbody = document.getElementById('inventory-tbody');
    
    // Tab 3: Procurement
    const createPOForm = document.getElementById('create-po-form');
    const poSelectMaterial = document.getElementById('po-select-material');
    const poSelectSupplier = document.getElementById('po-select-supplier');
    const poPrice = document.getElementById('po-price');
    const poQuantity = document.getElementById('po-quantity');
    const poMoq = document.getElementById('po-moq');
    const poSubmitBtn = document.getElementById('po-submit-btn');
    const poListTbody = document.getElementById('po-list-tbody'); 
    let supplierDataCache = [];
    
    // Tab 4: Finance 
    const financeTbody = document.getElementById('finance-tbody'); 
    const paymentHistoryTbody = document.getElementById('payment-history-tbody');

    // Tab 5: Forecast
    const forecastProductSelect = document.getElementById('forecast-product-select');
    const forecastHorizonSelect = document.getElementById('forecast-horizon-select');
    const forecastMae = document.getElementById('forecast-mae');
    const forecastRmse = document.getElementById('forecast-rmse');
    const forecastMape = document.getElementById('forecast-mape');
    const raisePOBtn = document.getElementById('raise-po-btn');
    const poForecastDemand = document.getElementById('po-forecast-demand');
    const poCurrentStock = document.getElementById('po-current-stock');
    const poSuggestedQty = document.getElementById('po-suggested-qty');
    const poRecommendation = document.getElementById('po-recommendation');
    let currentForecastData = null; // stores latest PO suggestion

    // Modal
    const modal = document.getElementById('triage-modal');
    const modalTitle = document.getElementById('modal-title');
    const modalContent = document.getElementById('modal-content');
    const modalCloseBtn = document.getElementById('modal-close-btn');

    // Toast Notification
    const toast = document.getElementById('toast-notification');
    const toastContent = document.getElementById('toast-content');
    const toastMessage = document.getElementById('toast-message');

    // Chat
    const chatToggleBtn = document.getElementById('chat-toggle-btn');
    const chatPanel = document.getElementById('chat-panel');
    const chatCloseBtn = document.getElementById('chat-close-btn');
    const chatClearBtn = document.getElementById('chat-clear-btn');
    const chatMessages = document.getElementById('chat-messages');
    const chatSendForm = document.getElementById('chat-send-form');
    const chatInput = document.getElementById('chat-input');
    const chatSendBtn = document.getElementById('chat-send-btn');

    let currentUserRole = null;
    let toastTimeout = null;
    let isChatOpen = false;

    // --- Core Functions ---
    function showToast(message, isError = false) {
        if (toastTimeout) clearTimeout(toastTimeout);
        toastMessage.textContent = message;
        toastContent.className = isError ? 'max-w-xs rounded-md bg-red-50 p-4 shadow-lg ring-1 ring-red-200' : 'max-w-xs rounded-md bg-white p-4 shadow-lg ring-1 ring-black ring-opacity-5';
        toastMessage.className = isError ? 'text-sm font-medium text-red-800' : 'text-sm font-medium text-gray-900';
        toast.classList.remove('hidden', 'toast-hide');
        toast.classList.add('toast-show');
        toastTimeout = setTimeout(() => {
            toast.classList.remove('toast-show');
            toast.classList.add('toast-hide');
            setTimeout(() => toast.classList.add('hidden'), 300);
        }, 3000);
    }

    async function fetchCurrentUser() {
        try {
            const response = await fetch('/api/auth/current-user');
            if (!response.ok) { window.location.href = '/login'; return; }
            const data = await response.json();
            
            usernameSpan.textContent = data.user.username;
            roleSpan.textContent = data.user.role;
            currentUserRole = data.user.role;
            
            if (currentUserRole === 'admin') {
                roleSpan.classList.add('text-hul-blue');
                loadAdminDashboard();
            } else {
                roleSpan.classList.add('text-gray-700');
                adminOnlyCard.style.display = 'none';
                document.querySelector('[data-tab="procurement"]').style.display = 'none';
                document.querySelector('[data-tab="finance"]').style.display = 'none'; 
            }
            loadDashboardData();
        } catch (error) {
            console.error('Error fetching user:', error);
            window.location.href = '/login';
        }
    }

    async function loadDashboardData() {
        showToast('Refreshing dashboard data...');
        fetchPendingOrders();
        fetchPendingOrdersStat();
        fetchInventorySnapshot();
        //loadForecast();
        if (currentUserRole === 'admin') {
            loadAdminDashboard();
        }
    }

    async function loadAdminDashboard() {
        fetchOutstandingBalanceStat();
        loadProcurementForm(); 
        fetchPurchaseOrders();
        fetchInvoices(); 
        fetchPaymentHistory(); 
    }

    // --- Helper for API calls ---
    async function apiFetch(url) {
        const response = await fetch(url);
        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.message || `HTTP error! status: ${response.status}`);
        }
        return await response.json();
    }


    // --- Data Fetching Functions (Calling Procedures/Functions) ---

    async function fetchPendingOrdersStat() {
        try {
            const data = await apiFetch('/api/dashboard/stats/pending-orders');
            statPendingOrders.textContent = data.total;
        } catch (error) { 
            console.error('Error fetching pending orders stat:', error);
            statPendingOrders.textContent = 'Error'; 
        }
    }

    async function fetchOutstandingBalanceStat() {
        try {
            const data = await apiFetch('/api/dashboard/stats/outstanding-balance');
            statOutstandingBalance.textContent = `₹${data.balance}`;
        } catch (error) { 
            console.error('Error fetching balance stat:', error);
            statOutstandingBalance.textContent = 'Error'; 
        }
    }

    async function fetchPendingOrders() {
        try {
            const data = await apiFetch('/api/orders/pending');
            
            pendingOrdersTbody.innerHTML = '';
            if (data.data && data.data.length > 0) {
                data.data.forEach(order => {
                    const isBlocked = order.Stock_Status.includes('Blocked');
                    let rowClass = '';
                    let actionButton;

                    if (order.Status === 'Allocated - Ready to Ship') {
                        actionButton = `<button class="text-yellow-600 hover:text-opacity-80 font-semibold btn-deallocate" data-dist-id="${order.Dist_ID}">Deallocate</button>`;
                        rowClass = 'bg-green-50'; 
                    
                    } else if (order.Status === 'Pending PO') { 
                        actionButton = `<span class="px-2 py-1 text-xs font-medium text-yellow-800 bg-yellow-100 rounded-full">PO Raised</span>`;
                        rowClass = 'bg-yellow-50';
                    
                    } else if (isBlocked) { 
                        actionButton = `<button class="text-hul-red hover:text-opacity-80 font-semibold btn-triage" data-dist-id="${order.Dist_ID}">Triage</button>`;
                    
                    } else { 
                        actionButton = `<button class="text-status-green hover:text-opacity-80 font-semibold btn-allocate" data-dist-id="${order.Dist_ID}">Allocate</button>`;
                    }
                    
                    if (currentUserRole === 'warehouse') {
                        actionButton = `<span class="text-xs text-gray-400">Admin Action</span>`;
                    }

                    const row = document.createElement('tr'); 
                    row.innerHTML = `
                        <tr class="${rowClass}">
                            <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">${order.Dist_ID}</td>
                            <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${order.Cust_Name}</td>
                            <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${new Date(order.Order_Date).toLocaleDateString()}</td>
                            <td class="whitespace-nowrap px-3 py-4 text-sm font-medium ${isBlocked ? 'text-status-red' : 'text-status-green'}">
                                ${order.Stock_Status}
                            </td>
                            <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0 space-x-4">
                                ${actionButton}
                                <button class="text-gray-400 hover:text-gray-800 btn-cancel" data-dist-id="${order.Dist_ID}">Cancel</button>
                            </td>
                        </tr>
                    `;
                    pendingOrdersTbody.appendChild(row);
                });
            } else {
                pendingOrdersTbody.innerHTML = '<tr><td colspan="5" class="px-3 py-4 text-sm text-gray-500 text-center">No pending orders found.</td></tr>';
            }
        } catch (error) {
            console.error('Error fetching pending orders:', error);
            pendingOrdersTbody.innerHTML = '<tr><td colspan="5" class="px-3 py-4 text-sm text-gray-500 text-center">Error loading data.</td></tr>';
        }
    }
    
    async function fetchInventorySnapshot() {
        try {
            const data = await apiFetch('/api/inventory/snapshot');
            inventoryTbody.innerHTML = '';
            if (data.data && data.data.length > 0) {
                data.data.forEach(item => {
                    const row = document.createElement('tr');
                    row.innerHTML = `<td class="py-2 text-sm font-medium text-gray-800">${item.ProductName}</td><td class="py-2 text-sm text-gray-500">${item.Quantity}</td><td class="py-2 text-sm text-gray-400">${item.Unit}</td>`;
                    inventoryTbody.appendChild(row);
                });
            } else {
                inventoryTbody.innerHTML = '<tr><td colspan="3" class="py-2 text-sm text-gray-500">No inventory found.</td></tr>';
            }
        } catch (error) {
            console.error('Error fetching inventory snapshot:', error);
            inventoryTbody.innerHTML = '<tr><td colspan="3" class="py-2 text-sm text-red-600">Error loading data.</td></tr>';
        }
    }

    async function fetchPurchaseOrders() {
        try {
            const data = await apiFetch('/api/procurement/purchase-orders');
            poListTbody.innerHTML = '';
            if (data.data && data.data.length > 0) {
                data.data.forEach(po => {
                    const row = document.createElement('tr');
                    let statusClass = '';
                    if (po.Status === 'Pending') statusClass = 'text-status-yellow';
                    if (po.Status === 'Delivered') statusClass = 'text-status-green';

                    row.innerHTML = `
                        <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">${po.PO_ID}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${new Date(po.OrderDate).toLocaleDateString()}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${po.SupplierName}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${po.ProductName}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${po.Quantity}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm font-medium ${statusClass}">${po.Status}</td>
                    `;
                    poListTbody.appendChild(row);
                });
            } else {
                poListTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-gray-500 text-center">No purchase orders found.</td></tr>';
            }
        } catch (error) {
            console.error('Error fetching purchase orders:', error);
            poListTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-red-600 text-center">Error loading data.</td></tr>';
        }
    }
    
    async function fetchInvoices() {
        try {
            const data = await apiFetch('/api/finance/invoices');
            financeTbody.innerHTML = '';
            if (data.data && data.data.length > 0) {
                data.data.forEach(invoice => {
                    const row = document.createElement('tr');
                    let statusClass = '';
                    if (invoice.Status === 'Unpaid') statusClass = 'text-status-red';
                    if (invoice.Status === 'Partially Paid') statusClass = 'text-yellow-600';

                    row.innerHTML = `
                        <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">${invoice.Invoice_ID}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${invoice.Cust_Name}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">₹${invoice.Final_Amount.toFixed(2)}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm font-bold text-gray-700">₹${invoice.Remaining_Balance.toFixed(2)}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm font-medium ${statusClass}">${invoice.Status}</td>
                        <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
                            <button class="text-hul-blue hover:text-opacity-80 font-semibold btn-record-payment"
                                data-invoice-id="${invoice.Invoice_ID}"
                                data-remaining="${invoice.Remaining_Balance.toFixed(2)}">
                                Record Payment
                            </button>
                        </td>
                    `;
                    financeTbody.appendChild(row);
                });
            } else {
                financeTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-gray-500 text-center">No unpaid invoices found.</td></tr>';
            }
        } catch (error) {
            console.error('Error fetching invoices:', error);
            financeTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-red-600 text-center">Error loading data.</td></tr>';
        }
    }

    async function fetchPaymentHistory() {
        try {
            const data = await apiFetch('/api/finance/payment-history');
            paymentHistoryTbody.innerHTML = '';
            if (data.data && data.data.length > 0) {
                data.data.forEach(payment => {
                    const row = document.createElement('tr');
                    row.innerHTML = `
                        <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">${payment.Pay_ID}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${payment.Invoice_ID}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${new Date(payment.Pay_Date).toLocaleDateString()}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${payment.Cust_Name}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm font-medium text-gray-700">₹${payment.Amount_Paid.toFixed(2)}</td>
                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">${payment.Pay_Method}</td>
                    `;
                    paymentHistoryTbody.appendChild(row);
                });
            } else {
                paymentHistoryTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-gray-500 text-center">No payments found.</td></tr>';
            }
        } catch (error) {
            console.error('Error fetching payment history:', error);
            paymentHistoryTbody.innerHTML = '<tr><td colspan="6" class="px-3 py-4 text-sm text-red-600 text-center">Error loading data.</td></tr>';
        }
    }

    // --- Procurement Form Logic ---
    async function loadProcurementForm() {
        try {
            const data = await apiFetch('/api/products/raw-materials');
            if (!data.data) return;
            poSelectMaterial.innerHTML = '<option value="">-- Select a material --</option>';
            data.data.forEach(material => {
                const option = document.createElement('option');
                option.value = material.Product_ID;
                option.textContent = material.Name;
                poSelectMaterial.appendChild(option);
            });
        } catch (e) {
            console.error("Error loading raw materials:", e);
        }
    }

    poSelectMaterial.addEventListener('change', async () => {
        const materialId = poSelectMaterial.value;
        poSelectSupplier.innerHTML = '<option value="">-- Loading suppliers... --</option>';
        poSelectSupplier.disabled = true;
        poPrice.value = '';
        poSubmitBtn.disabled = true;
        poMoq.textContent = '0';

        if (!materialId) {
            poSelectSupplier.innerHTML = '<option value="">-- Select a material first --</option>';
            return;
        }

        try {
            const data = await apiFetch(`/api/suppliers/for-material/${materialId}`);
            if (!data.data || data.data.length === 0) {
                poSelectSupplier.innerHTML = '<option value="">-- No suppliers found --</option>';
                return;
            }

            poSelectSupplier.innerHTML = '<option value="">-- Select a supplier --</option>';
            supplierDataCache = data.data; 

            data.data.forEach(supplier => {
                const option = document.createElement('option');
                option.value = supplier.Supplier_ID;
                option.textContent = supplier.SupplierName;
                poSelectSupplier.appendChild(option);
            });
            poSelectSupplier.disabled = false;
        } catch (e) {
            console.error("Error loading suppliers:", e);
        }
    });

    poSelectSupplier.addEventListener('change', () => {
        const supplierId = poSelectSupplier.value;
        if (!supplierId) {
            poPrice.value = '';
            poMoq.textContent = '0';
            poSubmitBtn.disabled = true;
            return;
        }

        const supplier = supplierDataCache.find(s => s.Supplier_ID == supplierId);
        if (supplier) {
            poPrice.value = supplier.ContractPrice.toFixed(2);
            poQuantity.min = supplier.MOQ || 1;
            poQuantity.value = supplier.MOQ || 1;
            poMoq.textContent = supplier.MOQ || 0;
            poSubmitBtn.disabled = false;
        }
    });

    createPOForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const supplierId = poSelectSupplier.value;
        const productId = poSelectMaterial.value;
        const quantity = poQuantity.value;
        const unitPrice = poPrice.value;

        try {
            const response = await fetch('/api/procurement/purchase-orders', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    supplier_id: parseInt(supplierId),
                    product_id: parseInt(productId),
                    quantity: parseInt(quantity),
                    unit_price: parseFloat(unitPrice)
                })
            });
            const data = await response.json();
            if (!response.ok) throw new Error(data.message);
            
            showToast(data.message);
            fetchPurchaseOrders(); 
            createPOForm.reset();
            poSelectSupplier.innerHTML = '<option value="">-- Select a material first --</option>';
            poSelectSupplier.disabled = true;
            poPrice.value = '';
            poMoq.textContent = '0';
            poSubmitBtn.disabled = true;

        } catch (error) {
            showToast(error.message || 'PO creation failed.', true);
        }
    });

    // --- Tab Navigation ---
    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            tabButtons.forEach(btn => btn.classList.remove('active'));
            tabContents.forEach(content => content.classList.remove('active'));
            button.classList.add('active');
            document.getElementById(`tab-${button.dataset.tab}`).classList.add('active');

            // When forecast tab is clicked, resize/redraw the chart
            // because Plotly can't render into a hidden element
            if (button.dataset.tab === 'forecast') {
                const chartDiv = document.getElementById('forecast-chart');
                if (chartDiv && chartDiv.data) {
                    // Chart already rendered — just resize it
                    Plotly.relayout('forecast-chart', {});
                } else {
                    // Chart not rendered yet — render it now
                    loadForecast();
                }
            }
        });
    });

    // --- Event Listeners (User Actions) ---
    logoutBtn.addEventListener('click', async () => {
        await fetch('/api/auth/logout', { method: 'POST' });
        window.location.href = '/login';
    });
    
    refreshBtn.addEventListener('click', loadDashboardData);
    modalCloseBtn.addEventListener('click', () => modal.close());
    
    pendingOrdersTbody.addEventListener('click', async (e) => {
        const target = e.target.closest('button');
        if (!target) return;
        const distId = target.dataset.distId;
        if (!distId) return;
        if (currentUserRole !== 'admin') {
            showToast('Access denied. Warehouse users can only view.', true);
            return;
        }
        if (target.classList.contains('btn-allocate')) await handleAllocate(distId);
        if (target.classList.contains('btn-triage')) await handleTriage(distId, distId);
        if (target.classList.contains('btn-cancel')) await handleCancel(distId);
        if (target.classList.contains('btn-deallocate')) await handleDeallocate(distId); 
    });

    financeTbody.addEventListener('click', async (e) => {
        const target = e.target.closest('button');
        if (!target || !target.classList.contains('btn-record-payment')) return;

        const invoiceId = target.dataset.invoiceId;
        const remaining = target.dataset.remaining;

        modalTitle.textContent = `Record Payment for Invoice #${invoiceId}`;
        modalContent.innerHTML = `
            <form id="payment-form" class="space-y-4">
                <div>
                    <label for="payment-amount" class="block text-sm font-medium text-gray-700">Amount Paid</label>
                    <div class="relative mt-1 rounded-md shadow-sm">
                        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                            <span class="text-gray-500 sm:text-sm">₹</span>
                        </div>
                        <input type="number" id="payment-amount" value="${remaining}" step="0.01" min="0.01" max="${remaining}" required 
                               class="block w-full rounded-md border-0 py-1.5 pl-7 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-inset focus:ring-hul-blue sm:text-sm">
                    </div>
                </div>
                <div>
                    <label for="payment-method" class="block text-sm font-medium text-gray-700">Payment Method</label>
                    <select id="payment-method" class="mt-1 block w-full rounded-md border-0 py-1.5 pl-3 pr-10 text-gray-900 ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-hul-blue sm:text-sm">
                        <option>Bank Transfer</option>
                        <option>Credit Card</option>
                        <option>Cash</option>
                        <option>Other</option>
                    </select>
                </div>
                <div class="mt-6 flex justify-end">
                    <button type="submit" id="modal-confirm-payment" data-invoice-id="${invoiceId}" 
                            class="rounded-md bg-hul-blue px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-opacity-90">
                        Submit Payment
                    </button>
                </div>
            </form>
        `;
        modal.showModal();
    });

    async function handleAllocate(distId) {
        modalTitle.textContent = `Allocate Stock for Order #${distId}`;
        modalContent.innerHTML = '<p class="text-gray-500">Loading order details...</p>';
        modal.showModal();
        try {
            const data = await apiFetch(`/api/orders/details/${distId}`);
            let html = '<p class="text-sm text-gray-600 mb-4">Stock is available. Click to confirm allocation and create a shipment.</p>';
            html += '<table class="min-w-full divide-y divide-gray-200"><thead class="bg-gray-50"><tr><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Product</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Qty Ordered</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">In Stock</th></tr></thead>';
            html += '<tbody class="bg-white divide-y divide-gray-200">';
            data.data.forEach(item => {
                html += `<tr><td class="px-4 py-3 text-sm font-medium text-gray-900">${item.ProductName}</td><td class="px-4 py-3 text-sm text-gray-500">${item.Qty_Ordered}</td><td class="px-4 py-3 text-sm text-status-green font-medium">${item.Qty_In_Stock}</td></tr>`;
            });
            html += '</tbody></table>';
            html += `<div class="mt-6 flex justify-end"><button id="modal-confirm-allocate" data-dist-id="${distId}" class="rounded-md bg-status-green px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-opacity-90">Confirm & Allocate</Button></div>`;
            modalContent.innerHTML = html;
        } catch (e) {
            modalContent.innerHTML = `<p class="text-red-600">Error loading details: ${e.message}</p>`;
        }
    }

    async function handleTriage(distId) {
        modalTitle.textContent = `Triage Order #${distId}`;
        modalContent.innerHTML = '<p class="text-gray-500">Loading order details...</p>';
        modal.showModal();
        try {
            const data = await apiFetch(`/api/orders/details/${distId}`);
            let html = '<p class="text-sm text-gray-600 mb-4">This order is blocked. Review the shortfall and take action.</p>';
            html += '<table class="min-w-full divide-y divide-gray-200"><thead class="bg-gray-50"><tr><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Product</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Qty Ordered</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">In Stock</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Action</th></tr></thead>';
            html += '<tbody class="bg-white divide-y divide-gray-200">';
            data.data.forEach(item => {
                const shortfall = item.Qty_In_Stock - item.Qty_Ordered;
                const isShortfall = shortfall < 0;
                let rowClass = isShortfall ? 'bg-red-50' : '';
                let actionBtn = isShortfall ? `<button class="text-hul-blue font-medium text-sm btn-check-rm" data-product-id="${item.Product_ID}" data-qty-needed="${-shortfall}" data-dist-id="${distId}">Check Raw Materials</button>` : `<span class="text-status-green text-sm font-medium">In Stock</span>`;
                html += `<tr class="${rowClass}"><td class="px-4 py-3 text-sm font-medium text-gray-900">${item.ProductName}</td><td class="px-4 py-3 text-sm text-gray-500">${item.Qty_Ordered}</td><td class="px-4 py-3 text-sm ${isShortfall ? 'text-status-red' : 'text-status-green'} font-medium">${item.Qty_In_Stock}</td><td class="px-4 py-3 text-sm">${actionBtn}</td></tr>`;
            });
            html += '</tbody></table>';
            modalContent.innerHTML = html;
        } catch (e) {
            modalContent.innerHTML = `<p class="text-red-600">Error loading details: ${e.message}</p>`;
        }
    }
    
    async function handleCancel(distId) {
        if (!confirm(`Are you sure you want to cancel Order ID ${distId}? This will delete the order.`)) return; 
        try {
            const response = await fetch('/api/orders/cancel', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ dist_id: parseInt(distId) })
            });
            const data = await response.json();
            if (!response.ok) throw new Error(data.message);
            showToast(data.message);
            loadDashboardData();
        } catch (error) {
            showToast(error.message || 'Error canceling order.', true);
        }
    }
    
    async function handleDeallocate(distId) {
        if (!confirm(`Are you sure you want to deallocate Order ID ${distId}? This will return stock and delete the shipment.`)) return;
        try {
            const response = await fetch('/api/orders/deallocate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ dist_id: parseInt(distId) })
            });
            const data = await response.json();
            if (!response.ok) throw new Error(data.message);
            showToast(data.message);
            loadDashboardData(); 
        } catch (error) {
            showToast(error.message || 'Error deallocating order.', true);
        }
    }

    async function handleCheckRawMaterials(productId, qtyNeeded, distId) {
        modalTitle.textContent = `Raw Materials for Product #${productId}`;
        modalContent.innerHTML = '<p class="text-gray-500">Checking bill of items...</p>';
        try {
            const data = await apiFetch(`/api/products/raw-materials/${productId}/${qtyNeeded}`);
            let html = `<p class="text-sm text-gray-600 mb-4">The following raw materials are needed to produce ${qtyNeeded} units.</p>`;
            html += '<table class="min-w-full divide-y divide-gray-200"><thead class="bg-gray-50"><tr><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Raw Material</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Qty Required</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">In Stock</th><th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Action</th></tr></thead>';
            html += '<tbody class="bg-white divide-y divide-gray-200">';
            data.data.forEach(item => {
                const isShortfall = item.Shortfall < 0;
                let rowClass = isShortfall ? 'bg-red-50' : '';
                let actionBtn = isShortfall ? `<button class="text-hul-blue font-medium text-sm btn-find-suppliers" data-rm-id="${item.RawMaterialID}" data-qty-needed="${-item.Shortfall}" data-dist-id="${distId}">Find Suppliers</button>` : `<span class"text-status-green text-sm font-medium">In Stock</span>`;
                html += `<tr class="${rowClass}"><td class="px-4 py-3 text-sm font-medium text-gray-900">${item.RawMaterialName}</td><td class="px-4 py-3 text-sm text-gray-500">${item.Qty_Required}</td><td class="px-4 py-3 text-sm ${isShortfall ? 'text-status-red' : 'text-status-green'} font-medium">${item.Qty_In_Stock || 0}</td><td class="px-4 py-3 text-sm">${actionBtn}</td></tr>`;
            });
            html += '</tbody></table>';
            modalContent.innerHTML = html;
        } catch (e) {
            modalContent.innerHTML = `<p class="text-red-600">Error loading raw materials: ${e.message}</p>`;
        }
    }

    async function handleFindSuppliers(rawMaterialId, qtyNeeded, distId) {
        modalTitle.textContent = `Suppliers for Raw Material #${rawMaterialId}`;
        modalContent.innerHTML = '<p class="text-gray-500">Finding suppliers...</p>';
        try {
            const data = await apiFetch(`/api/suppliers/for-material/${rawMaterialId}`);
            let html = `<p class="text-sm text-gray-600 mb-4">Found ${data.data.length} supplier(s). Select one to create a Purchase Order.</p>`;
            html += '<div class="space-y-4">';
            data.data.forEach(item => {
                const finalQty = Math.max(qtyNeeded, item.MOQ || 0);
                html += `
                <div class="border border-gray-200 rounded-md p-4">
                    <h4 class="font-medium text-gray-900">${item.SupplierName}</h4>
                    <p class="text-sm text-gray-500">Price: ₹${item.ContractPrice} | MOQ: ${item.MOQ}</p>
                    <form class="mt-4 space-y-3 modal-po-form" data-supplier-id="${item.Supplier_ID}" data-rm-id="${rawMaterialId}" data-price="${item.ContractPrice}" data-dist-id="${distId}">
                        <label class="block text-sm font-medium text-gray-700">Order Quantity: (Min. ${finalQty})</label>
                        <input type="number" value="${finalQty}" min="${finalQty}" class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-inset focus:ring-hul-blue sm:text-sm">
                        <button type="submit" class="w-full rounded-md bg-hul-blue px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-opacity-9Oh">Create Purchase Order</button>
                    </form>
                </div>`;
            });
            html += '</div>';
            modalContent.innerHTML = html;
        } catch (e) {
            modalContent.innerHTML = `<p class="text-red-600">Error loading suppliers: ${e.message}</p>`;
        }
    }
    
    // --- Event Listener for Modal (Event Delegation) ---
    modalContent.addEventListener('click', async (e) => {
        const target = e.target.closest('button');
        if (!target) return;

        if (target.id === 'modal-confirm-allocate') {
            const distId = target.dataset.distId;
            try {
                const response = await fetch('/api/orders/allocate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ dist_id: parseInt(distId) })
                });
                const data = await response.json();
                if (!response.ok) throw new Error(data.message);
                showToast(data.message);
                modal.close();
                loadDashboardData();
            } catch (err) {
                showToast(err.message || 'Allocation failed.', true);
            }
        }

        if (target.id === 'modal-confirm-payment') {
            e.preventDefault(); 
            const invoiceId = target.dataset.invoiceId;
            const amount = document.getElementById('payment-amount').value;
            const method = document.getElementById('payment-method').value;

            if (!amount || parseFloat(amount) <= 0) {
                showToast('Invalid amount.', true);
                return;
            }
            
            try {
                const response = await fetch('/api/finance/payments', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        invoice_id: parseInt(invoiceId),
                        amount_paid: parseFloat(amount),
                        pay_method: method
                    })
                });
                const data = await response.json();
                if (!response.ok) throw new Error(data.message);
                
                showToast(data.message);
                modal.close();
                fetchInvoices(); 
                fetchPaymentHistory(); 
                fetchOutstandingBalanceStat(); // <-- THIS IS THE FIX
            } catch (err) {
                showToast(err.message, true);
            }
        }

        if (target.classList.contains('btn-check-rm')) {
            const productId = target.dataset.productId;
            const qtyNeeded = target.dataset.qtyNeeded;
            const distId = target.dataset.distId;
            await handleCheckRawMaterials(productId, qtyNeeded, distId);
        }
        if (target.classList.contains('btn-find-suppliers')) {
            const rmId = target.dataset.rmId;
            const qtyNeeded = target.dataset.qtyNeeded;
            const distId = target.dataset.distId;
            await handleFindSuppliers(rmId, qtyNeeded, distId);
        }
    });
    
    modalContent.addEventListener('submit', async (e) => {
        if (e.target.classList.contains('modal-po-form')) {
            e.preventDefault();
            const form = e.target;
            const supplierId = form.dataset.supplierId;
            const rmId = form.dataset.rmId;
            const price = form.dataset.price;
            const distId = form.dataset.distId;
            const quantity = form.querySelector('input').value;
            try {
                const response = await fetch('/api/orders/generate-po', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        dist_id: parseInt(distId),
                        supplier_id: parseInt(supplierId),
                        product_id: parseInt(rmId),
                        quantity: parseInt(quantity),
                        unit_price: parseFloat(price)
                    })
                });
                const data = await response.json();
                if (!response.ok) throw new Error(data.message);
                showToast(data.message);
                modal.close();
                loadDashboardData();
            } catch (err) {
                showToast(err.message || 'PO creation failed.', true);
            }
        }
    });

    
    // --- Initial Load ---
    // --- Forecast Functions ---

    async function loadForecast() {
        const productId = forecastProductSelect.value;
        const horizon = forecastHorizonSelect.value;

        // Reset UI
        forecastMae.textContent = '--';
        forecastRmse.textContent = '--';
        forecastMape.textContent = '--%';
        poForecastDemand.textContent = '--';
        poCurrentStock.textContent = '--';
        poSuggestedQty.textContent = '--';
        poRecommendation.textContent = 'Loading...';
        raisePOBtn.disabled = true;
        Plotly.purge('forecast-chart');

        try {
            // Fetch forecast chart data and PO suggestion in parallel
            const [forecastData, poData] = await Promise.all([
                apiFetch(`/api/forecast/${productId}?horizon=${horizon}`),
                apiFetch(`/api/forecast/suggested-po/${productId}?horizon=30`)
            ]);

            const fd = forecastData.data;
            const po = poData.data;
            currentForecastData = po;

            // Update metrics cards
            if (fd.metrics) {
                forecastMae.textContent = fd.metrics.MAE ? fd.metrics.MAE.toLocaleString() : '--';
                forecastRmse.textContent = fd.metrics.RMSE ? fd.metrics.RMSE.toLocaleString() : '--';
                forecastMape.textContent = fd.metrics.MAPE ? `${fd.metrics.MAPE}%` : '--%';
            }

            // Update PO suggestion cards
            poForecastDemand.textContent = po.forecasted_demand.toLocaleString();
            poCurrentStock.textContent = po.current_inventory.toLocaleString();
            poSuggestedQty.textContent = po.suggested_po_qty.toLocaleString();
            poRecommendation.textContent = po.recommendation;
            raisePOBtn.disabled = po.suggested_po_qty <= 0;

            // Build Plotly chart
            renderForecastChart(fd);

        } catch (err) {
            console.error('Forecast error:', err);
            showToast('Error loading forecast: ' + err.message, true);
            poRecommendation.textContent = 'Failed to load forecast.';
        }
    }

    function renderForecastChart(fd) {
        const histDates = fd.historical.map(d => d.ds);
        const histValues = fd.historical.map(d => d.y);
        const fcDates = fd.forecast.map(d => d.ds);
        const fcValues = fd.forecast.map(d => d.yhat);
        const fcLower = fd.forecast.map(d => d.lower);
        const fcUpper = fd.forecast.map(d => d.upper);

        // Confidence band — upper then lower reversed (Plotly fill trick)
        const bandX = [...fcDates, ...fcDates.slice().reverse()];
        const bandY = [...fcUpper, ...fcLower.slice().reverse()];

        const traces = [
            // Confidence band (rendered first so it sits behind lines)
            {
                x: bandX, y: bandY,
                fill: 'toself',
                fillcolor: 'rgba(0, 75, 147, 0.1)',
                line: { color: 'transparent' },
                name: '80% Confidence Band',
                type: 'scatter',
                hoverinfo: 'skip',
                showlegend: true
            },
            // Historical actuals
            {
                x: histDates, y: histValues,
                mode: 'lines+markers',
                name: 'Historical Demand',
                line: { color: '#004b93', width: 2 },
                marker: { size: 4 },
                type: 'scatter'
            },
            // Forecast line
            {
                x: fcDates, y: fcValues,
                mode: 'lines+markers',
                name: 'Forecast',
                line: { color: '#e60023', width: 2, dash: 'dash' },
                marker: { size: 4 },
                type: 'scatter'
            }
        ];

        const layout = {
            margin: { t: 20, r: 20, b: 60, l: 60 },
            xaxis: {
                title: 'Month',
                tickangle: -30,
                tickformat: '%b %Y'
            },
            yaxis: { title: `Units (${fd.unit})` },
            legend: { orientation: 'h', y: -0.2 },
            hovermode: 'x unified',
            paper_bgcolor: 'white',
            plot_bgcolor: '#f9fafb',
            shapes: [{
                // Vertical line separating historical from forecast
                type: 'line',
                x0: fd.historical[fd.historical.length - 1]?.ds,
                x1: fd.historical[fd.historical.length - 1]?.ds,
                y0: 0, y1: 1,
                yref: 'paper',
                line: { color: '#6b7280', width: 1, dash: 'dot' }
            }]
        };

        Plotly.newPlot('forecast-chart', traces, layout, { responsive: true, displayModeBar: false });
    }

    // Product or horizon change → reload forecast
    forecastProductSelect.addEventListener('change', loadForecast);
    forecastHorizonSelect.addEventListener('change', loadForecast);

    // Raise PO button — navigates to Procurement tab with a toast
    raisePOBtn.addEventListener('click', () => {
        if (!currentForecastData || currentForecastData.suggested_po_qty <= 0) return;
        showToast(`Suggested PO: ${currentForecastData.suggested_po_qty.toLocaleString()} units of ${currentForecastData.product_name}. Use the Procurement tab to raise the PO.`);
        // Switch to procurement tab
        document.querySelector('[data-tab="procurement"]').click();
    });

    function toggleChatPanel(forceOpen = null) {
        if (!chatPanel) return;
        const shouldOpen = forceOpen === null ? !isChatOpen : forceOpen;
        isChatOpen = shouldOpen;
        chatPanel.classList.toggle('translate-x-[110%]', !shouldOpen);
        chatPanel.classList.toggle('translate-x-0', shouldOpen);
        if (shouldOpen && chatInput) {
            chatInput.focus();
        }
    }

    function appendChatBubble(message, sender) {
        if (!chatMessages) return;
        const row = document.createElement('div');
        row.className = sender === 'user' ? 'flex justify-end' : 'flex justify-start';

        const bubble = document.createElement('div');
        bubble.className = sender === 'user'
            ? 'max-w-[85%] rounded-lg bg-hul-blue px-3 py-2 text-sm text-white'
            : 'max-w-[85%] rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-900';
        bubble.textContent = message;

        row.appendChild(bubble);
        chatMessages.appendChild(row);
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    async function sendChatMessage(event) {
        event.preventDefault();
        const userInput = chatInput.value.trim();
        if (!userInput) {
            showToast('Please enter a message before sending.', true);
            return;
        }

        appendChatBubble(userInput, 'user');
        chatInput.value = '';
        chatSendBtn.disabled = true;
        chatSendBtn.classList.add('opacity-50', 'cursor-not-allowed');

        try {
            const response = await fetch('/api/chat', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ message: userInput })
            });
            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.message || 'Failed to send chat message.');
            }
            appendChatBubble(data.response || 'No response received.', 'assistant');
        } catch (error) {
            showToast(error.message, true);
            appendChatBubble('Sorry, I could not get a response right now.', 'assistant');
        } finally {
            chatSendBtn.disabled = false;
            chatSendBtn.classList.remove('opacity-50', 'cursor-not-allowed');
            chatInput.focus();
        }
    }

    async function clearChatMessages() {
        try {
            const response = await fetch('/api/chat/clear', { method: 'POST' });
            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.message || 'Failed to clear chat.');
            }
            chatMessages.innerHTML = '';
            showToast('Chat history cleared.');
        } catch (error) {
            showToast(error.message, true);
        }
    }

    if (chatToggleBtn && chatPanel && chatSendForm && chatInput && chatSendBtn && chatMessages) {
        chatToggleBtn.addEventListener('click', () => toggleChatPanel());
        if (chatCloseBtn) {
            chatCloseBtn.addEventListener('click', () => toggleChatPanel(false));
        }
        if (chatClearBtn) {
            chatClearBtn.addEventListener('click', clearChatMessages);
        }
        chatSendForm.addEventListener('submit', sendChatMessage);
    }

    // --- Initial Load ---
    fetchCurrentUser();
});
