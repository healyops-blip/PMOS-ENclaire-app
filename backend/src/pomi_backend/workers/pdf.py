"""Server-side PDF generation from immutable report snapshots."""

from __future__ import annotations

import hashlib
import textwrap
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from pomi_backend.config import Settings
from pomi_backend.db.models import ReportFile, ReportSnapshot
from pomi_backend.db.models.auth import utc_now


def run_pdf_once(factory: sessionmaker[Session], settings: Settings) -> bool:
    with factory() as session:
        file = session.scalar(
            select(ReportFile)
            .where(ReportFile.generation_status == "pending")
            .order_by(ReportFile.id)
            .limit(1)
        )
        if file is None:
            return False
        file.generation_status = "processing"
        file_id = file.id
        session.commit()
    try:
        with factory() as session:
            file = session.get(ReportFile, file_id)
            report = session.get(ReportSnapshot, file.report_id) if file else None
            if file is None or report is None:
                return True
            relative_path = Path("reports") / report.id / f"{file.id}.pdf"
            final_path = settings.storage_root / relative_path
            final_path.parent.mkdir(parents=True, exist_ok=True)
            _render_report(final_path, report)
            content = final_path.read_bytes()
            file.storage_path = relative_path.as_posix()
            file.file_hash = hashlib.sha256(content).hexdigest()
            file.file_size_bytes = len(content)
            file.generation_status = "succeeded"
            file.generated_at = utc_now()
            file.failure_reason = None
            session.commit()
    except Exception:
        with factory() as session:
            file = session.get(ReportFile, file_id)
            if file is not None:
                file.generation_status = "failed"
                file.failure_reason = "PDF generation failed."
                session.commit()
    return True


def _render_report(path: Path, report: ReportSnapshot) -> None:
    pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    document = canvas.Canvas(str(path), pagesize=A4)
    width, height = A4
    del width
    text = document.beginText(48, height - 52)
    text.setFont("STSong-Light", 16)
    text.textLine("Pomi 复诊准备报告")
    text.setFont("STSong-Light", 10)
    text.textLine(f"报告编号：{report.id}")
    text.textLine(f"生成时间：{report.generated_at.isoformat()}")
    text.textLine("")
    summary = report.snapshot.get("summary", {})
    profile = summary.get("profile", {})
    lines = [
        f"用户：{profile.get('nickname') or '未填写'}",
        f"主要状况：{profile.get('primary_condition') or '未填写'}",
        f"患者自述：{summary.get('patient_note_text') or '无'}",
        f"当前用药数量：{len(summary.get('current_medications', []))}",
        f"已确认指标数量：{len(summary.get('latest_observations', []))}",
        "",
        "本报告整理用户确认的记录，用于复诊前准备，不构成诊断或治疗建议。",
    ]
    for line in lines:
        for wrapped in textwrap.wrap(str(line), width=70) or [""]:
            if text.getY() < 52:
                document.drawText(text)
                document.showPage()
                text = document.beginText(48, height - 52)
                text.setFont("STSong-Light", 10)
            text.textLine(wrapped)
    document.drawText(text)
    document.save()
