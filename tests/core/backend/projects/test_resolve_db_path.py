def test_uses_xdg_data_home_when_set(run_resolve, tmp_path):
    xdg = tmp_path / "xdg"
    code, out, err = run_resolve(["/home/user/myproject"], env={"XDG_DATA_HOME": str(xdg)})
    assert code == 0
    assert out == str(xdg / "brd" / "brd.db")


def test_falls_back_to_home_local_share_when_no_xdg(run_resolve, tmp_path):
    home = tmp_path / "home"
    code, out, err = run_resolve(["/home/user/myproject"], env={"HOME": str(home)})
    assert code == 0
    assert out == str(home / ".local" / "share" / "brd" / "brd.db")


def test_the_watched_path_does_not_depend_on_which_project_is_open(run_resolve, tmp_path):
    # brd keeps every project's data in one consolidated database, so the
    # path Panel.qml watches is the same no matter which project is current.
    home = tmp_path / "home"
    project = tmp_path / "code" / "myproject"
    project.mkdir(parents=True)

    code_abs, out_abs, _ = run_resolve([str(project)], env={"HOME": str(home)})
    code_rel, out_rel, _ = run_resolve(["myproject"], env={"HOME": str(home)}, cwd=str(tmp_path / "code"))

    assert code_abs == 0 and code_rel == 0
    assert out_abs == out_rel == str(home / ".local" / "share" / "brd" / "brd.db")


def test_missing_argv_exits_nonzero_and_prints_nothing(run_resolve, tmp_path):
    code, out, err = run_resolve([], env={"HOME": str(tmp_path)})
    assert code != 0
    assert out == ""


def test_empty_argv_exits_nonzero_and_prints_nothing(run_resolve, tmp_path):
    code, out, err = run_resolve([""], env={"HOME": str(tmp_path)})
    assert code != 0
    assert out == ""


def test_missing_home_and_xdg_exits_nonzero_and_prints_nothing(run_resolve):
    code, out, err = run_resolve(["/home/user/myproject"], env={})
    assert code != 0
    assert out == ""
