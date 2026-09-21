"""backfill real pending-report creation events

Revision ID: 20260921_09
Revises: 20260921_08
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "20260921_09"
down_revision: str | None = "20260921_08"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # These are real reports created before history existed. Only the known
    # creation event is reconstructed; claim/resolve history is not invented.
    op.execute(sa.text("""
        INSERT INTO notification_events
            (recipient_user_id, fire_report_id, event_type, title, body, created_at)
        SELECT r.reporter_id, r.id, 'report_created',
               'تم إرسال بلاغ الحريق',
               'يمكنك متابعة حالة بلاغك من التنبيهات.', r.reported_at
        FROM fire_reports r
        WHERE r.status = 'pending'
          AND NOT EXISTS (
              SELECT 1 FROM notification_events n
              WHERE n.fire_report_id = r.id
                AND n.recipient_user_id = r.reporter_id
                AND n.event_type = 'report_created'
          )
    """))
    op.execute(sa.text("""
        INSERT INTO notification_events
            (recipient_municipality_id, fire_report_id, event_type, title, body, created_at)
        SELECT r.municipality_id, r.id, 'report_created',
               'بلاغ حريق جديد', 'تم تسجيل بلاغ حريق جديد بالقرب منك', r.reported_at
        FROM fire_reports r
        WHERE r.status = 'pending'
          AND NOT EXISTS (
              SELECT 1 FROM notification_events n
              WHERE n.fire_report_id = r.id
                AND n.recipient_municipality_id = r.municipality_id
                AND n.event_type = 'report_created'
          )
    """))
    op.execute(sa.text("""
        INSERT INTO notification_events
            (recipient_user_id, fire_report_id, event_type, title, body, created_at)
        SELECT v.user_id, r.id, 'new_report',
               'بلاغ حريق جديد', 'تم تسجيل بلاغ حريق جديد بالقرب منك', r.reported_at
        FROM fire_reports r
        JOIN volunteers v ON v.municipality_id = r.municipality_id
        JOIN users u ON u.id = v.user_id AND u.is_active = true
        WHERE r.status = 'pending'
          AND NOT EXISTS (
              SELECT 1 FROM notification_events n
              WHERE n.fire_report_id = r.id
                AND n.recipient_user_id = v.user_id
                AND n.event_type = 'new_report'
          )
    """))


def downgrade() -> None:
    # The backfilled rows are genuine report history and should be retained.
    pass
