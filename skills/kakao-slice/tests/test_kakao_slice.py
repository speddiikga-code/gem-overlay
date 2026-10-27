import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "kakao_slice.py"
spec = importlib.util.spec_from_file_location("kakao_slice", SCRIPT)
ks = importlib.util.module_from_spec(spec)
sys.modules["kakao_slice"] = ks
spec.loader.exec_module(ks)

PC_KO = """\
홍길동 님과 카카오톡 대화
저장한 날짜 : 2026-10-28 09:00:00

--------------- 2026년 10월 25일 일요일 ---------------
[홍길동] [오전 12:05] 자정 넘었다
[김철수] [오전 9:30] 좋은 아침
--------------- 2026년 10월 27일 화요일 ---------------
이영희님이 들어왔습니다.
[홍길동] [오후 12:30] 점심 메뉴
1. 김밥

2. 라면
[김철수] [오후 1:19] 라면 좋아요
김철수님이 나갔습니다.
"""

PC_EN = """\
KakaoTalk Chats with Alice
Date Saved : Oct 28, 2026 at 9:00 AM

--------------- Sunday, October 25, 2026 ---------------
[Alice] [12:05 AM] past midnight
--------------- Tuesday, October 27, 2026 ---------------
Bob joined this chatroom.
[Bob] [12:30 PM] Lunch?
[Alice] [1:19 PM] Sure
see you there
"""

ANDROID_KO = """\
홍길동 님과 카카오톡 대화
저장한 날짜 : 2026년 10월 28일 오전 9:00

2026년 10월 25일 일요일
2026년 10월 25일 오전 12:05, 홍길동 : 자정

2026년 10월 27일 화요일
2026년 10월 27일 오후 12:30, 김철수님이 들어왔습니다.
2026년 10월 27일 오후 12:31, 김철수 : 점심
뭐 먹지
2026년 10월 27일 오후 1:19, 홍길동 : 라면 : 짜파게티
"""

IOS_KO = """\
홍길동 님과 카카오톡 대화
저장한 날짜 : 2026. 10. 28. 오전 9:00

2026년 10월 25일 일요일
2026. 10. 25. 오전 12:05, 홍길동 : 자정
2026년 10월 27일 화요일
2026. 10. 27. 오후 12:30, 김철수 : 점심
2026. 10. 27. 13:19, 홍길동 : 24시간 표기
2026. 10. 27. 13:20, 이영희님이 나갔습니다.
"""

EN_MOBILE = """\
KakaoTalk Chats with Alice
Date Saved : Oct 28, 2026 at 9:00 AM

Sunday, October 25, 2026
October 25, 2026 at 12:05 AM, Alice : past midnight
Tuesday, October 27, 2026
October 27, 2026 at 12:30 PM, Bob : lunch?
October 27, 2026 at 12:31 PM, Carol joined this chatroom.
"""

EN_SHORT = """\
10/25/26, 12:05 AM - Alice: past midnight
10/27/26, 12:30 PM - Bob: lunch?
see you
10/27/26, 12:31 PM - Carol joined
"""

MULTI_DAY = """\
2026년 10월 1일 오전 10:00, 홍길동 : 시작
2026년 10월 15일 오후 3:00, 김철수 : Meeting at 3
2026년 10월 20일 오후 4:00, 홍길동 : 회의 자료 올렸어요
2026년 10월 20일 오후 4:05, Alice : thanks
2026년 10월 27일 오후 1:19, 김철수 : 오늘 회의 취소
"""


def rendered(text: str) -> list[str]:
    return [message.render() for message in ks.parse(text.split("\n"))]


@pytest.mark.parametrize(
    ("chat", "expected"),
    [
        (
            PC_KO,
            [
                "2026-10-25 00:05 홍길동: 자정 넘었다",
                "2026-10-25 09:30 김철수: 좋은 아침",
                "2026-10-27 12:30 홍길동: 점심 메뉴\n  1. 김밥\n\n  2. 라면",
                "2026-10-27 13:19 김철수: 라면 좋아요",
            ],
        ),
        (
            PC_EN,
            [
                "2026-10-25 00:05 Alice: past midnight",
                "2026-10-27 12:30 Bob: Lunch?",
                "2026-10-27 13:19 Alice: Sure\n  see you there",
            ],
        ),
        (
            ANDROID_KO,
            [
                "2026-10-25 00:05 홍길동: 자정",
                "2026-10-27 12:31 김철수: 점심\n  뭐 먹지",
                "2026-10-27 13:19 홍길동: 라면 : 짜파게티",
            ],
        ),
        (
            IOS_KO,
            [
                "2026-10-25 00:05 홍길동: 자정",
                "2026-10-27 12:30 김철수: 점심",
                "2026-10-27 13:19 홍길동: 24시간 표기",
            ],
        ),
        (EN_MOBILE, ["2026-10-25 00:05 Alice: past midnight", "2026-10-27 12:30 Bob: lunch?"]),
        (EN_SHORT, ["2026-10-25 00:05 Alice: past midnight", "2026-10-27 12:30 Bob: lunch?\n  see you"]),
    ],
    ids=["pc-ko", "pc-en", "android-ko", "ios-ko", "en-mobile", "en-short"],
)
def test_formats(chat, expected):
    assert rendered(chat) == expected


@pytest.mark.parametrize(
    ("hour", "ampm", "expected"),
    [
        (12, "오전", 0),
        (12, "오후", 12),
        (1, "오후", 13),
        (11, "오전", 11),
        (12, "AM", 0),
        (12, "PM", 12),
        (13, None, 13),
    ],
)
def test_twelve_oclock(hour, ampm, expected):
    assert ks.hour24(hour, ampm) == expected


def test_system_lines_are_not_attached():
    texts = [message.text for message in ks.parse(PC_KO.split("\n"))]
    assert not any("들어왔습니다" in text or "나갔습니다" in text or "저장한 날짜" in text for text in texts)
    assert texts[1] == "좋은 아침"


def test_line_like_another_format_stays_text():
    chat = "2026년 10월 27일 오후 1:00, 홍길동 : 붙여넣기\n[김철수] [오후 1:01] 예전 메시지\n"
    assert rendered(chat) == ["2026-10-27 13:00 홍길동: 붙여넣기\n  [김철수] [오후 1:01] 예전 메시지"]


def test_bare_date_inside_pc_message_keeps_day():
    chat = (
        "--------------- 2026년 10월 27일 화요일 ---------------\n"
        "[홍길동] [오후 1:00] 다음 모임\n"
        "2026년 11월 3일 화요일\n"
        "[김철수] [오후 1:01] 좋아\n"
    )
    assert [message.when.date().isoformat() for message in ks.parse(chat.split("\n"))] == ["2026-10-27"] * 2


def run(capsys, tmp_path, text, *args):
    chat = tmp_path / "chat.txt"
    chat.write_text(text, encoding="utf-8")
    code = ks.main([str(chat), *args])
    out, err = capsys.readouterr()
    return code, out, err


def test_list_counts(capsys, tmp_path):
    code, out, _ = run(capsys, tmp_path, PC_KO, "--list")
    assert code == 0
    assert out == "2026-10-25  2\n2026-10-27  2\ntotal 4 messages on 2 dates\n"


def test_months(capsys, tmp_path):
    _, out, _ = run(capsys, tmp_path, MULTI_DAY, "--months")
    assert out == "2026-10  5\ntotal 5 messages on 1 month\n"


@pytest.mark.parametrize(
    ("args", "expected"),
    [
        (["--date", "2026-10-20"], ["10-20 16:00", "10-20 16:05"]),
        (["--from", "2026-10-15", "--to", "2026-10-20"], ["10-15 15:00", "10-20 16:00", "10-20 16:05"]),
        (["--from", "2026-10-16"], ["10-20 16:00", "10-20 16:05", "10-27 13:19"]),
        (["--to", "2026-10-01"], ["10-01 10:00"]),
        (["--last", "2"], ["10-20 16:00", "10-20 16:05", "10-27 13:19"]),
        (["--last", "10"], ["10-01 10:00", "10-15 15:00", "10-20 16:00", "10-20 16:05", "10-27 13:19"]),
        (["--sender", "홍", "--sender", "alice"], ["10-01 10:00", "10-20 16:00", "10-20 16:05"]),
        (["--grep", "MEETING"], ["10-15 15:00"]),
        (["--grep", "회의"], ["10-20 16:00", "10-27 13:19"]),
        (["--grep", "회의", "--sender", "김철수"], ["10-27 13:19"]),
        (["--last", "1", "--grep", "회의"], ["10-27 13:19"]),
    ],
)
def test_filters(capsys, tmp_path, args, expected):
    code, out, _ = run(capsys, tmp_path, MULTI_DAY, *args)
    assert code == 0
    assert [line[5:16] for line in out.splitlines()] == expected


def test_list_respects_selection(capsys, tmp_path):
    _, out, _ = run(capsys, tmp_path, MULTI_DAY, "--list", "--sender", "김철수")
    assert out == "2026-10-15  1\n2026-10-27  1\ntotal 2 messages on 2 dates\n"


def test_stats(capsys, tmp_path):
    _, out, _ = run(capsys, tmp_path, MULTI_DAY, "--stats")
    assert out == "2  홍길동\n2  김철수\n1  Alice\ntotal 5 messages from 3 senders\n"


def test_output_file(capsys, tmp_path):
    target = tmp_path / "slice.txt"
    code, out, err = run(capsys, tmp_path, PC_KO, "--date", "2026-10-27", "-o", str(target))
    assert code == 0
    assert out == ""
    assert "wrote 2 messages" in err
    assert target.read_text(encoding="utf-8").splitlines() == [
        "2026-10-27 12:30 홍길동: 점심 메뉴",
        "  1. 김밥",
        "",
        "  2. 라면",
        "2026-10-27 13:19 김철수: 라면 좋아요",
    ]


def test_no_match(capsys, tmp_path):
    code, out, err = run(capsys, tmp_path, MULTI_DAY, "--date", "2026-10-02")
    assert (code, out) == (0, "")
    assert "no messages match" in err


@pytest.mark.parametrize("encoding", ["utf-8-sig", "utf-16", "cp949"])
def test_bom_crlf_and_encodings(capsys, tmp_path, encoding):
    chat = tmp_path / "chat.txt"
    chat.write_bytes(MULTI_DAY.replace("\n", "\r\n").encode(encoding))
    assert ks.main([str(chat), "--date", "2026-10-01"]) == 0
    out, _ = capsys.readouterr()
    assert out == "2026-10-01 10:00 홍길동: 시작\n"


@pytest.mark.parametrize("text", ["hello\nthis is not a chat export\n", ""])
def test_unknown_format(capsys, tmp_path, text):
    code, out, err = run(capsys, tmp_path, text, "--list")
    assert code == 1
    assert out == ""
    assert "no KakaoTalk messages found" in err
    for fmt in ks.FORMATS:
        assert fmt.name in err


@pytest.mark.parametrize(
    "args",
    [
        ["--date", "2026-13-01"],
        ["--date", "yesterday"],
        ["--from", "2026-10-27", "--to", "2026-10-01"],
        ["--date", "2026-10-27", "--last", "2"],
        ["--from", "2026-10-01", "--last", "2"],
        ["--last", "0"],
        ["--last", "x"],
    ],
)
def test_bad_arguments(capsys, tmp_path, args):
    with pytest.raises(SystemExit) as exit_info:
        run(capsys, tmp_path, MULTI_DAY, *args)
    assert exit_info.value.code == 2


def test_missing_file(tmp_path):
    with pytest.raises(SystemExit) as exit_info:
        ks.main([str(tmp_path / "missing.txt"), "--list"])
    assert exit_info.value.code == 2


def test_script_prints_utf8(tmp_path):
    chat = tmp_path / "chat.txt"
    chat.write_text(PC_KO, encoding="utf-8")
    result = subprocess.run([sys.executable, str(SCRIPT), str(chat), "--last", "1"], capture_output=True, check=False)
    assert result.returncode == 0
    assert result.stdout.decode("utf-8").splitlines()[0] == "2026-10-27 12:30 홍길동: 점심 메뉴"
