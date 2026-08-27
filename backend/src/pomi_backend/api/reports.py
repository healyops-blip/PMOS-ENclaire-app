"""Authenticated deterministic report snapshot API."""

from fastapi import APIRouter, Request, status

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import ReportSnapshotServiceDependency
from pomi_backend.schemas.reports import ReportCreate

router = APIRouter(prefix="/api/reports", tags=["reports"])


@router.post("/preflight")
def report_preflight(
    payload: ReportCreate,
    request: Request,
    service: ReportSnapshotServiceDependency,
) -> dict:
    return success(request, service.preflight(payload))


@router.post("", status_code=status.HTTP_201_CREATED)
def create_report(
    payload: ReportCreate,
    request: Request,
    service: ReportSnapshotServiceDependency,
) -> dict:
    report, reused = service.create(payload)
    response = success(request, report)
    if reused:
        response["meta"] = {"reused": True}
    return response


@router.get("")
def list_reports(request: Request, service: ReportSnapshotServiceDependency) -> dict:
    items = service.list()
    return success(
        request,
        {
            "items": items,
            "next_cursor": None,
            "has_more": False,
        },
    )


@router.get("/{report_id}")
def get_report(
    report_id: str,
    request: Request,
    service: ReportSnapshotServiceDependency,
) -> dict:
    return success(request, service.get(report_id))
