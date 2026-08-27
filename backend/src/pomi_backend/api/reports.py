"""Patient-note, immutable report, and PDF API."""

from typing import Annotated

from fastapi import APIRouter, Header, Query, Request, status
from fastapi.responses import FileResponse

from pomi_backend.api.business import success
from pomi_backend.api.dependencies import ReportServiceDependency
from pomi_backend.schemas.reports import PatientNoteInput, ReportCreate
from pomi_backend.services.reports import note_data, pdf_data, report_list_data

router = APIRouter(prefix="/api", tags=["reports"])
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=128)]


@router.get("/patient-notes")
def get_latest_note(request: Request, service: ReportServiceDependency) -> dict:
    note = service.latest_note()
    return success(request, note_data(note) if note else None)


@router.post("/patient-notes", status_code=status.HTTP_201_CREATED)
def create_note(
    payload: PatientNoteInput,
    request: Request,
    service: ReportServiceDependency,
) -> dict:
    return success(request, note_data(service.save_note(payload)))


@router.put("/patient-notes/{note_id}")
def update_note(
    note_id: str,
    payload: PatientNoteInput,
    request: Request,
    service: ReportServiceDependency,
) -> dict:
    return success(request, note_data(service.save_note(payload, note_id)))


@router.get("/reports")
def list_reports(
    request: Request,
    service: ReportServiceDependency,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> dict:
    reports = service.reports(limit, cursor)
    page = reports[:limit]
    return success(
        request,
        {
            "items": [report_list_data(report) for report in page],
            "next_cursor": page[-1].generated_at.isoformat() if len(reports) > limit else None,
            "has_more": len(reports) > limit,
        },
    )


@router.post("/reports", status_code=status.HTTP_201_CREATED)
def create_report(
    payload: ReportCreate,
    request: Request,
    service: ReportServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    return success(
        request,
        report_list_data(service.create_report(payload, idempotency_key)),
    )


@router.get("/reports/{report_id}")
def get_report(
    report_id: str,
    request: Request,
    service: ReportServiceDependency,
) -> dict:
    return success(request, service.report_detail(report_id))


@router.post("/reports/{report_id}/pdf", status_code=status.HTTP_202_ACCEPTED)
def request_report_pdf(
    report_id: str,
    request: Request,
    service: ReportServiceDependency,
    idempotency_key: IdempotencyKey,
) -> dict:
    del idempotency_key
    return success(request, pdf_data(service.request_pdf(report_id), report_id))


@router.get("/reports/{report_id}/pdf")
def get_report_pdf(
    report_id: str,
    request: Request,
    service: ReportServiceDependency,
) -> dict:
    return success(request, pdf_data(service.pdf(report_id), report_id))


@router.get("/reports/{report_id}/pdf/file", response_class=FileResponse)
def download_report_pdf(
    report_id: str,
    service: ReportServiceDependency,
) -> FileResponse:
    return FileResponse(
        service.pdf_path(report_id),
        media_type="application/pdf",
        filename=f"pomi-report-{report_id}.pdf",
    )
