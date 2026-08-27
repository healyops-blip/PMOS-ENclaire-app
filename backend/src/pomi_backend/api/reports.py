"""Authenticated immutable report and private PDF APIs."""

from typing import Annotated

from fastapi import APIRouter, Header, Request, status
from fastapi.responses import FileResponse

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import (
    ReportFileServiceDependency,
    ReportSnapshotServiceDependency,
)
from pomi_backend.schemas.reports import ReportCreate
from pomi_backend.services.report_files import report_file_data

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
    return success(request, service.detail(report_id))


@router.post("/{report_id}/pdf", status_code=status.HTTP_202_ACCEPTED)
def create_report_pdf(
    report_id: str,
    request: Request,
    service: ReportFileServiceDependency,
    idempotency_key: Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)],
) -> dict:
    # The client key prevents accidental transport retries; artifact identity is derived only
    # from report_id + immutable snapshot_hash + template_version by the service.
    del idempotency_key
    report_file, created = service.create_or_retry(report_id)
    response = success(request, report_file_data(report_file))
    response["meta"] = {"reused": not created}
    return response


@router.get("/{report_id}/pdf")
def get_report_pdf(
    report_id: str,
    request: Request,
    service: ReportFileServiceDependency,
) -> dict:
    return success(request, report_file_data(service.status(report_id)))


@router.get(
    "/{report_id}/pdf/file",
    response_class=FileResponse,
    responses={
        200: {"content": {"application/pdf": {"schema": {"type": "string", "format": "binary"}}}}
    },
)
def download_report_pdf(
    report_id: str,
    service: ReportFileServiceDependency,
) -> FileResponse:
    report_file, path = service.download(report_id)
    return FileResponse(
        path,
        media_type="application/pdf",
        filename=f"pomi-report-{report_file.report_id}.pdf",
        headers={
            "Cache-Control": "private, no-store, max-age=0",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
        },
    )
