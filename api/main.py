
import logging
from fastapi import FastAPI, Depends, HTTPException, Request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from api.database import engine, Base
from api.routes import returns, sales, purchases, user, category, customer, product, login, supplier, auth, stock, purchases_receive, payments, debts, config
from api.routes import proformas, invoices, inventory
from api.routes import employees, payroll
from api.routes import setup as setup_router
# Import models so create_all picks them up
from api.models import Proforma, Invoice, InventoryRecord  # noqa: F401
from fastapi.staticfiles import StaticFiles
from fastapi.encoders import jsonable_encoder

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory="api/static"), name="static")

app.include_router(user.router)
app.include_router(login.router)
app.include_router(auth.router)
app.include_router(category.router)
app.include_router(supplier.router)
app.include_router(product.router)
app.include_router(purchases.router)
app.include_router(purchases_receive.router)
app.include_router(customer.router)
app.include_router(sales.router)
app.include_router(stock.router)
app.include_router(returns.router, prefix="/returns", tags=["Returns"])
app.include_router(payments.router)
app.include_router(debts.router)
app.include_router(config.router)
app.include_router(proformas.router)
app.include_router(invoices.router)
app.include_router(inventory.router)
app.include_router(employees.router)
app.include_router(payroll.router)
app.include_router(setup_router.router, prefix="/api")

@app.on_event("startup")
def on_startup():
    Base.metadata.create_all(bind=engine)

@app.get("/health", include_in_schema=False)
async def health_root():
    return {"status": "ok"}

@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return {}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = {}
    for err in exc.errors():
        field = err["loc"][-1]
        message = err["msg"]
        errors[field] = message

    return JSONResponse(
        status_code=422,
        content={
            "message": "Erreur de validation",
            "errors": errors
        }
    )

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"message": exc.detail}
    )



@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    _logger = logging.getLogger("pos.api")
    _logger.error("Unhandled exception on %s %s: %s", request.method, request.url.path, exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"message": "Erreur interne du serveur"},
    )



# @app.get("/")
# def root():
#     return {"message": "Hello POS"}


#   python.exe -m  uvicorn api.main:app --reload
