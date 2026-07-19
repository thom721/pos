from typing import List


# ---------------------------------------------------------------------------
# Permission constants — format: "resource.action"
# ---------------------------------------------------------------------------
class P:
    # Users
    USERS_CREATE   = "users.create"
    USERS_READ     = "users.read"
    USERS_UPDATE   = "users.update"
    USERS_DELETE   = "users.delete"

    # Products
    PRODUCTS_CREATE  = "products.create"
    PRODUCTS_READ    = "products.read"
    PRODUCTS_UPDATE  = "products.update"
    PRODUCTS_DELETE  = "products.delete"

    # Categories
    CATEGORIES_CREATE  = "categories.create"
    CATEGORIES_READ    = "categories.read"
    CATEGORIES_UPDATE  = "categories.update"
    CATEGORIES_DELETE  = "categories.delete"

    # Suppliers
    SUPPLIERS_CREATE  = "suppliers.create"
    SUPPLIERS_READ    = "suppliers.read"
    SUPPLIERS_UPDATE  = "suppliers.update"
    SUPPLIERS_DELETE  = "suppliers.delete"

    # Customers
    CUSTOMERS_CREATE  = "customers.create"
    CUSTOMERS_READ    = "customers.read"
    CUSTOMERS_UPDATE  = "customers.update"
    CUSTOMERS_DELETE  = "customers.delete"

    # Sales
    SALES_CREATE    = "sales.create"
    SALES_READ      = "sales.read"
    SALES_UPDATE    = "sales.update"
    SALES_CANCEL    = "sales.cancel"
    SALES_DISCOUNT  = "sales.discount"

    # Purchases
    PURCHASES_CREATE   = "purchases.create"
    PURCHASES_READ     = "purchases.read"
    PURCHASES_UPDATE   = "purchases.update"
    PURCHASES_RECEIVE  = "purchases.receive"

    # Payments
    PAYMENTS_CREATE  = "payments.create"
    PAYMENTS_READ    = "payments.read"

    # Debts
    DEBTS_READ = "debts.read"

    # Returns
    RETURNS_CREATE  = "returns.create"
    RETURNS_READ    = "returns.read"

    # Stock
    STOCK_READ    = "stock.read"
    STOCK_ADJUST  = "stock.adjust"

    # Inventory
    INVENTORY_CREATE  = "inventory.create"
    INVENTORY_READ    = "inventory.read"

    # Reports
    REPORTS_READ      = "reports.read"
    REPORTS_READ_ALL  = "reports.read_all"

    # Config
    CONFIG_READ    = "config.read"
    CONFIG_UPDATE  = "config.update"

    # Proformas
    PROFORMAS_CREATE  = "proformas.create"
    PROFORMAS_READ    = "proformas.read"
    PROFORMAS_UPDATE  = "proformas.update"
    PROFORMAS_DELETE  = "proformas.delete"

    # Invoices
    INVOICES_CREATE  = "invoices.create"
    INVOICES_READ    = "invoices.read"
    INVOICES_UPDATE  = "invoices.update"
    INVOICES_DELETE  = "invoices.delete"

    # Employees (HR profiles)
    EMPLOYEES_CREATE = "employees.create"
    EMPLOYEES_READ   = "employees.read"
    EMPLOYEES_UPDATE = "employees.update"

    # Loans & credit purchases
    LOANS_CREATE  = "loans.create"
    LOANS_READ    = "loans.read"
    LOANS_APPROVE = "loans.approve"

    # Payroll
    PAYROLL_CREATE  = "payroll.create"
    PAYROLL_READ    = "payroll.read"
    PAYROLL_PROCESS = "payroll.process"
    PAYROLL_PAY     = "payroll.pay"

    # Cashier sessions
    SESSIONS_OPEN  = "sessions.open"
    SESSIONS_CLOSE = "sessions.close"
    SESSIONS_READ  = "sessions.read"

    # Audit trail
    AUDIT_READ = "audit.read"

    # Warehouses (depots)
    WAREHOUSES_CREATE = "warehouses.create"
    WAREHOUSES_READ   = "warehouses.read"
    WAREHOUSES_UPDATE = "warehouses.update"
    WAREHOUSES_DELETE = "warehouses.delete"


# ---------------------------------------------------------------------------
# Role → permissions mapping
# "all" is a wildcard that grants everything
# ---------------------------------------------------------------------------
ROLE_PERMISSIONS: dict[str, set[str]] = {
    "admin": {"all"},

    "manager": {
        P.USERS_READ,
        P.PRODUCTS_CREATE, P.PRODUCTS_READ, P.PRODUCTS_UPDATE, P.PRODUCTS_DELETE,
        P.CATEGORIES_CREATE, P.CATEGORIES_READ, P.CATEGORIES_UPDATE, P.CATEGORIES_DELETE,
        P.SUPPLIERS_CREATE, P.SUPPLIERS_READ, P.SUPPLIERS_UPDATE, P.SUPPLIERS_DELETE,
        P.CUSTOMERS_CREATE, P.CUSTOMERS_READ, P.CUSTOMERS_UPDATE, P.CUSTOMERS_DELETE,
        P.SALES_CREATE, P.SALES_READ, P.SALES_UPDATE, P.SALES_CANCEL, P.SALES_DISCOUNT,
        P.PURCHASES_CREATE, P.PURCHASES_READ, P.PURCHASES_UPDATE, P.PURCHASES_RECEIVE,
        P.PAYMENTS_CREATE, P.PAYMENTS_READ,
        P.DEBTS_READ,
        P.RETURNS_CREATE, P.RETURNS_READ,
        P.STOCK_READ, P.STOCK_ADJUST,
        P.INVENTORY_CREATE, P.INVENTORY_READ,
        P.REPORTS_READ, P.REPORTS_READ_ALL,
        P.CONFIG_READ, P.CONFIG_UPDATE,
        P.PROFORMAS_CREATE, P.PROFORMAS_READ, P.PROFORMAS_UPDATE, P.PROFORMAS_DELETE,
        P.INVOICES_CREATE, P.INVOICES_READ, P.INVOICES_UPDATE, P.INVOICES_DELETE,
        P.EMPLOYEES_CREATE, P.EMPLOYEES_READ, P.EMPLOYEES_UPDATE,
        P.LOANS_CREATE, P.LOANS_READ, P.LOANS_APPROVE,
        P.PAYROLL_CREATE, P.PAYROLL_READ, P.PAYROLL_PROCESS, P.PAYROLL_PAY,
        P.SESSIONS_OPEN, P.SESSIONS_CLOSE, P.SESSIONS_READ,
        P.AUDIT_READ,
        P.WAREHOUSES_CREATE, P.WAREHOUSES_READ, P.WAREHOUSES_UPDATE, P.WAREHOUSES_DELETE,
    },

    "cashier": {
        P.SALES_CREATE, P.SALES_READ, P.SALES_UPDATE, P.SALES_CANCEL,
        P.CUSTOMERS_CREATE, P.CUSTOMERS_READ, P.CUSTOMERS_UPDATE,
        P.PRODUCTS_READ,
        P.CATEGORIES_READ,
        P.PAYMENTS_CREATE, P.PAYMENTS_READ,
        P.DEBTS_READ,
        P.RETURNS_CREATE, P.RETURNS_READ,
        P.REPORTS_READ,
        P.PROFORMAS_CREATE, P.PROFORMAS_READ, P.PROFORMAS_UPDATE,
        P.INVOICES_CREATE, P.INVOICES_READ, P.INVOICES_UPDATE,
        P.CONFIG_READ,
        P.SESSIONS_OPEN, P.SESSIONS_CLOSE,
        P.WAREHOUSES_READ,
    },

    "stock_manager": {
        P.PRODUCTS_CREATE, P.PRODUCTS_READ, P.PRODUCTS_UPDATE, P.PRODUCTS_DELETE,
        P.CATEGORIES_CREATE, P.CATEGORIES_READ, P.CATEGORIES_UPDATE, P.CATEGORIES_DELETE,
        P.SUPPLIERS_CREATE, P.SUPPLIERS_READ, P.SUPPLIERS_UPDATE, P.SUPPLIERS_DELETE,
        P.PURCHASES_CREATE, P.PURCHASES_READ, P.PURCHASES_UPDATE, P.PURCHASES_RECEIVE,
        P.RETURNS_CREATE, P.RETURNS_READ,
        P.STOCK_READ, P.STOCK_ADJUST,
        P.INVENTORY_CREATE, P.INVENTORY_READ,
        P.CONFIG_READ,
        P.WAREHOUSES_READ, P.WAREHOUSES_UPDATE,
    },
}


def load_roles_from_db(db_roles: list) -> None:
    """
    Merge DB-stored role permissions into ROLE_PERMISSIONS.
    Called at startup and after any role update.
    db_roles: list of Role ORM objects.
    """
    for role in db_roles:
        perms = role.permissions or []
        ROLE_PERMISSIONS[role.name] = set(perms)


def get_all_role_names() -> list[str]:
    return list(ROLE_PERMISSIONS.keys())


def has_permission(
    user_permissions: List[str],
    user_roles: List[str],
    required: str,
) -> bool:
    """Return True if the user has the required permission."""
    perms = set(user_permissions or [])
    roles = list(user_roles or [])

    # Wildcard bypass
    if "all" in perms:
        return True

    # Direct permission match
    if required in perms:
        return True

    # Role-derived permissions
    for role in roles:
        role_perms = ROLE_PERMISSIONS.get(role, set())
        if "all" in role_perms or required in role_perms:
            return True

    return False
