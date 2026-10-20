"""Exercise a real dashboard approval against disposable CSV files."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from review_ops import load_results
from voc_ops import run


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec("streamlit"), "Streamlit is not installed")
class DashboardTests(unittest.TestCase):
    def test_overview_and_report_download_render_for_demo(self) -> None:
        from streamlit.testing.v1 import AppTest

        setup = (
            "from pathlib import Path\nimport dashboard\n"
            "dashboard.SOURCE = dashboard.ROOT / 'output' / 'openai' / 'classified_voc.csv'\n"
            "dashboard.REVIEWED = dashboard.ROOT / 'output' / 'openai' / 'reviewed_voc.csv'\n"
        )
        app = AppTest.from_string(
            setup + "dashboard.render_overview(dashboard.SOURCE, dashboard.REVIEWED)",
            default_timeout=20,
        ).run()
        self.assertFalse(app.exception)
        self.assertTrue(any("유형별 의견" in item.value for item in app.markdown))
        self.assertTrue(any("우선순위별 의견" in item.value for item in app.markdown))
        self.assertTrue(any("먼저 확인할 의견" in item.value for item in app.markdown))
        self.assertTrue(any("접수 패턴" in item.value for item in app.markdown))
        self.assertTrue(any("제품 영역별 의견" in item.value for item in app.markdown))

        history = AppTest.from_string(
            setup + "dashboard.render_history(dashboard.available_batches())",
            default_timeout=20,
        ).run()
        self.assertFalse(history.exception)
        self.assertTrue(any("결과 내보내기" in item.value for item in history.markdown))

    def test_upload_page_explains_demo_data_and_temporary_storage(self) -> None:
        from streamlit.testing.v1 import AppTest

        app = AppTest.from_string("import dashboard\ndashboard.main()", default_timeout=20).run()
        self.assertFalse(app.exception)
        menu = next(radio for radio in app.radio if radio.label == "메뉴")
        menu.set_value("CSV 가져오기").run()
        self.assertFalse(app.exception)
        warnings = "\n".join(item.value for item in app.warning)
        self.assertIn("가상 데모 CSV만 업로드하세요", warnings)
        self.assertIn("재시작이나 재배포 후 보존되지 않을 수 있습니다", warnings)

    def test_uploaded_csv_creates_separate_run_and_discards_raw_copy(self) -> None:
        import dashboard

        output_root = ROOT / "output"
        output_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=output_root) as directory:
            sandbox = Path(directory).resolve()
            self.assertTrue(sandbox.is_relative_to(ROOT.resolve()))
            payload = (
                "voc_id,received_at,channel,platform,app_version,screen,user_text\n"
                "UP-001,2026-10-20,beta_form,web,unknown,login,"
                "test@example.com으로 로그인하면 앱이 종료돼요.\n"
            ).encode("utf-8-sig")
            with patch.object(dashboard, "ROOT", sandbox), patch.object(
                dashboard, "BATCHES", sandbox / "output" / "batches"
            ):
                batch_id, log = dashboard.import_batch(payload, "규칙 초안")
                source = dashboard.BATCHES / batch_id / "classified_voc.csv"
                self.assertEqual(log["input_count"], 1)
                self.assertTrue(source.exists())
                self.assertIn("[EMAIL]", load_results(source)[0]["user_text_redacted"])
                self.assertFalse(list((sandbox / "output").glob("voc-upload-*.csv")))

    def test_approval_saves_review_without_changing_classifier_output(self) -> None:
        from streamlit.testing.v1 import AppTest

        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            run(ROOT / "data" / "development_voc.csv", target)
            source = target / "classified_voc.csv"
            reviewed = target / "reviewed_voc.csv"
            script = (
                "from pathlib import Path\n"
                "import dashboard\n"
                f"dashboard.SOURCE = Path({str(source)!r})\n"
                f"dashboard.REVIEWED = Path({str(reviewed)!r})\n"
                "dashboard.main()\n"
            )
            app = AppTest.from_string(script, default_timeout=20).run()
            self.assertFalse(app.exception)
            self.assertEqual(sum(row["review_status"] == "PENDING" for row in load_results(source)), 17)
            self.assertEqual(app.button[0].label, "운영 기준 결과 승인")
            app.button[0].click().run()
            self.assertFalse(app.exception)
            self.assertTrue(reviewed.exists())
            self.assertEqual(sum(row["review_status"] == "PENDING" for row in load_results(source)), 17)
            self.assertEqual(sum(row["review_status"] == "PENDING" for row in load_results(reviewed)), 16)


if __name__ == "__main__":
    unittest.main()
