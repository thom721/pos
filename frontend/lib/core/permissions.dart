/// Permission constants — must stay in sync with api/core/permissions.py
abstract class Perm {
  // Users
  static const usersCreate = 'users.create';
  static const usersRead   = 'users.read';
  static const usersUpdate = 'users.update';
  static const usersDelete = 'users.delete';

  // Products
  static const productsCreate = 'products.create';
  static const productsRead   = 'products.read';
  static const productsUpdate = 'products.update';
  static const productsDelete = 'products.delete';

  // Categories
  static const categoriesCreate = 'categories.create';
  static const categoriesRead   = 'categories.read';
  static const categoriesUpdate = 'categories.update';
  static const categoriesDelete = 'categories.delete';

  // Suppliers
  static const suppliersCreate = 'suppliers.create';
  static const suppliersRead   = 'suppliers.read';
  static const suppliersUpdate = 'suppliers.update';
  static const suppliersDelete = 'suppliers.delete';

  // Customers
  static const customersCreate = 'customers.create';
  static const customersRead   = 'customers.read';
  static const customersUpdate = 'customers.update';
  static const customersDelete = 'customers.delete';

  // Sales
  static const salesCreate   = 'sales.create';
  static const salesRead     = 'sales.read';
  static const salesUpdate   = 'sales.update';
  static const salesCancel   = 'sales.cancel';
  static const salesDiscount = 'sales.discount'; // appliquer une remise caisse

  // Purchases
  static const purchasesCreate  = 'purchases.create';
  static const purchasesRead    = 'purchases.read';
  static const purchasesUpdate  = 'purchases.update';
  static const purchasesReceive = 'purchases.receive';

  // Payments
  static const paymentsCreate = 'payments.create';
  static const paymentsRead   = 'payments.read';

  // Debts
  static const debtsRead = 'debts.read';

  // Returns
  static const returnsCreate = 'returns.create';
  static const returnsRead   = 'returns.read';

  // Stock
  static const stockRead   = 'stock.read';
  static const stockAdjust = 'stock.adjust';

  // Inventory
  static const inventoryCreate = 'inventory.create';
  static const inventoryRead   = 'inventory.read';

  // Reports
  static const reportsRead    = 'reports.read';
  static const reportsReadAll = 'reports.read_all';

  // Cashier sessions
  static const sessionsOpen  = 'sessions.open';
  static const sessionsClose = 'sessions.close';
  static const sessionsRead  = 'sessions.read';

  // Config
  static const configRead   = 'config.read';
  static const configUpdate = 'config.update';

  // Dépôts (warehouses)
  static const warehousesCreate = 'warehouses.create';
  static const warehousesRead   = 'warehouses.read';
  static const warehousesUpdate = 'warehouses.update';
  static const warehousesDelete = 'warehouses.delete';

  // Proformas
  static const proformasCreate = 'proformas.create';
  static const proformasRead   = 'proformas.read';
  static const proformasUpdate = 'proformas.update';
  static const proformasDelete = 'proformas.delete';

  // Invoices
  static const invoicesCreate = 'invoices.create';
  static const invoicesRead   = 'invoices.read';
  static const invoicesUpdate = 'invoices.update';
  static const invoicesDelete = 'invoices.delete';

  // Employees (HR)
  static const employeesCreate = 'employees.create';
  static const employeesRead   = 'employees.read';
  static const employeesUpdate = 'employees.update';

  // Loans
  static const loansCreate  = 'loans.create';
  static const loansRead    = 'loans.read';
  static const loansApprove = 'loans.approve';

  // Payroll
  static const payrollCreate  = 'payroll.create';
  static const payrollRead    = 'payroll.read';
  static const payrollProcess = 'payroll.process';
  static const payrollPay     = 'payroll.pay';
}

/// Permissions regroupées par rôle — miroir de ROLE_PERMISSIONS en Python.
/// Utilisé côté client uniquement pour l'affichage conditionnel.
const Map<String, Set<String>> rolePermissions = {
  'admin': {'all'},
  'manager': {
    Perm.usersRead,
    Perm.productsCreate, Perm.productsRead, Perm.productsUpdate, Perm.productsDelete,
    Perm.categoriesCreate, Perm.categoriesRead, Perm.categoriesUpdate, Perm.categoriesDelete,
    Perm.suppliersCreate, Perm.suppliersRead, Perm.suppliersUpdate, Perm.suppliersDelete,
    Perm.customersCreate, Perm.customersRead, Perm.customersUpdate, Perm.customersDelete,
    Perm.salesCreate, Perm.salesRead, Perm.salesUpdate, Perm.salesCancel, Perm.salesDiscount,
    Perm.purchasesCreate, Perm.purchasesRead, Perm.purchasesUpdate, Perm.purchasesReceive,
    Perm.paymentsCreate, Perm.paymentsRead,
    Perm.debtsRead,
    Perm.returnsCreate, Perm.returnsRead,
    Perm.stockRead, Perm.stockAdjust,
    Perm.inventoryCreate, Perm.inventoryRead,
    Perm.reportsRead, Perm.reportsReadAll,
    Perm.sessionsOpen, Perm.sessionsClose, Perm.sessionsRead,
    Perm.configRead, Perm.configUpdate,
    Perm.proformasCreate, Perm.proformasRead, Perm.proformasUpdate, Perm.proformasDelete,
    Perm.invoicesCreate, Perm.invoicesRead, Perm.invoicesUpdate, Perm.invoicesDelete,
    Perm.employeesCreate, Perm.employeesRead, Perm.employeesUpdate,
    Perm.loansCreate, Perm.loansRead, Perm.loansApprove,
    Perm.payrollCreate, Perm.payrollRead, Perm.payrollProcess, Perm.payrollPay,
  },
  'cashier': {
    Perm.salesCreate, Perm.salesRead, Perm.salesUpdate, Perm.salesCancel,
    Perm.customersCreate, Perm.customersRead, Perm.customersUpdate,
    Perm.productsRead,
    Perm.categoriesRead,
    Perm.paymentsCreate, Perm.paymentsRead,
    Perm.debtsRead,
    Perm.reportsRead,
    Perm.sessionsOpen, Perm.sessionsClose,
    Perm.proformasCreate, Perm.proformasRead, Perm.proformasUpdate,
    Perm.invoicesCreate, Perm.invoicesRead, Perm.invoicesUpdate,
    Perm.configRead,
  },
  'stock_manager': {
    Perm.productsCreate, Perm.productsRead, Perm.productsUpdate, Perm.productsDelete,
    Perm.categoriesCreate, Perm.categoriesRead, Perm.categoriesUpdate, Perm.categoriesDelete,
    Perm.suppliersCreate, Perm.suppliersRead, Perm.suppliersUpdate, Perm.suppliersDelete,
    Perm.purchasesCreate, Perm.purchasesRead, Perm.purchasesUpdate, Perm.purchasesReceive,
    Perm.returnsCreate, Perm.returnsRead,
    Perm.stockRead, Perm.stockAdjust,
    Perm.inventoryCreate, Perm.inventoryRead,
    Perm.configRead,
  },
};
