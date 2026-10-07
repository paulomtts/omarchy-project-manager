import QtQuick
import QtTest
import "../../../core/domain/brd-extras.js" as Extras

TestCase {
  name: "DomainBrdExtras"

  // Verbatim shapes from the installed brd: `brd export`'s data object. Note
  // what it does NOT carry: an exported issue has no `blocks` and no `kind`,
  // and `cards` is a nested tree whose children carry their own `blocked_by`.
  // An issue's blocked cards are therefore read back off the card tree.
  function exportData() {
    return {
      brd_export: 1,
      cards: [
        { id: "c1", title: "Card One", description: "d", status: "blocked", blocked_by: ["i1"],
          created_at: "2026-09-20T09:00:00+00:00", updated_at: "2026-09-20T09:00:00+00:00",
          children: [
            { id: "c2", title: "Child", description: null, status: "blocked", blocked_by: ["i3"],
              created_at: "2026-09-20T09:30:00+00:00", updated_at: "2026-09-20T09:30:00+00:00",
              children: [] }
          ] },
        { id: "c3", title: "Card Three", description: null, status: "blocked", blocked_by: ["i3"],
          created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-20T10:00:00+00:00",
          children: [] }
      ],
      issues: [
        { id: "i1", title: "Broken build", body: "It fails.", status: "open", close_reason: null,
          created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
        { id: "i2", title: "Old bug", body: "", status: "closed", close_reason: "resolved",
          created_at: "2026-09-10T10:00:00+00:00", updated_at: "2026-09-11T10:00:00+00:00" },
        { id: "i3", title: "Newer", body: "", status: "open", close_reason: null,
          created_at: "2026-09-21T10:00:00+00:00", updated_at: "2026-09-25T10:00:00+00:00" }
      ],
      documents: [{ id: "d1", title: "Doc", source_path: "docs/a.md", content: "# Design\n\nbody\n",
                    content_hash: "h", created_at: "2026-09-20T10:00:00+00:00",
                    updated_at: "2026-09-20T10:00:00+00:00" }],
      comments: [
        { id: "m2", entity_id: "c1", author: "paulo", body: "second", created_at: "2026-09-24T12:00:00+00:00" },
        { id: "m1", entity_id: "c1", author: "claude", body: "first", created_at: "2026-09-24T09:00:00+00:00" },
        { id: "m3", entity_id: "i1", author: "paulo", body: "on the issue", created_at: "2026-09-24T09:00:00+00:00" }
      ],
      tags: [{ entity_id: "d1", tag: "design" }],
      refs: [{ src_id: "i1", dst_id: "c1", origin: "explicit" },
             { src_id: "c1", dst_id: "i1", origin: "explicit" }]
    }
  }
  // The real brd_export 2 envelope: the same collections, nested per project.
  function exportV2() {
    var flat = exportData()
    var entry = { project: { id: "p1", name: "proj", root_path: "/tmp/proj", created_at: "2026-09-20T09:00:00+00:00" } }
    ;["cards", "issues", "documents", "comments", "tags", "refs"].forEach(function(k) { entry[k] = flat[k] })
    return { brd_export: 2, projects: [entry] }
  }
  function line(data) { return JSON.stringify({ ok: true, data: data }) }
  function ids(list) { return list.map(function(x) { return x.id }).join(",") }

  function test_comments_are_indexed_by_entity_oldest_first() {
    var map = Extras.indexComments(exportData())
    compare(Object.keys(map).sort().join(","), "c1,i1")
    compare(map["c1"].map(function(c) { return c.body }).join(","), "first,second")
    compare(map["c1"][0].author, "claude")
    compare(map["c1"][0].entityId, "c1")
    compare(map["i1"].length, 1)
  }

  function test_comments_survive_missing_fields() {
    var map = Extras.indexComments({ comments: [{ id: "m", entity_id: "c1" }, { entity_id: "c1" }, null] })
    compare(map["c1"].length, 2)
    compare(map["c1"][0].author, "")
    compare(map["c1"][0].body, "")
    compare(map["c1"][0].createdAt, "")
  }

  function test_refs_are_indexed_both_ways() {
    var map = Extras.indexRefs(exportData())
    compare(map["i1"].refs.join(","), "c1")
    compare(map["i1"].referencedBy.join(","), "c1")
    compare(map["c1"].refs.join(","), "i1")
    compare(Object.keys(Extras.indexRefs({})).length, 0, "no refs means no entries")
    compare(Object.keys(Extras.indexRefs({ refs: [{ src_id: "a" }, { dst_id: "b" }, null] })).length, 0,
            "a ref missing an end is skipped")
  }

  // Ordering equal timestamps must not rest on the engine's sort being stable.
  function test_comments_with_the_same_timestamp_keep_the_export_order() {
    var same = "2026-09-24T09:00:00+00:00"
    var map = Extras.indexComments({ comments: [
      { id: "a", entity_id: "c1", body: "a", created_at: same },
      { id: "b", entity_id: "c1", body: "b", created_at: same },
      { id: "c", entity_id: "c1", body: "c", created_at: same },
      { id: "d", entity_id: "c1", body: "d", created_at: same },
      { id: "e", entity_id: "c1", body: "e", created_at: same },
      { id: "f", entity_id: "c1", body: "f", created_at: same },
      { id: "g", entity_id: "c1", body: "g", created_at: same },
      { id: "h", entity_id: "c1", body: "h", created_at: same },
      { id: "i", entity_id: "c1", body: "i", created_at: same },
      { id: "j", entity_id: "c1", body: "j", created_at: same },
      { id: "k", entity_id: "c1", body: "k", created_at: same }] })
    compare(map["c1"].map(function(c) { return c.body }).join(","), "a,b,c,d,e,f,g,h,i,j,k")
  }

  function test_issues_are_open_first_then_newest_updated() {
    var data = exportData()
    var list = Extras.issueList(data, Extras.indexComments(data))
    compare(ids(list), "i3,i1,i2")
    compare(list[1].commentCount, 1)
    compare(list[0].commentCount, 0)
    compare(list[1].closeReason, "")
    compare(list[2].closeReason, "resolved")
    compare(list[1].blocks.join(","), "c1")
  }

  // The export drops an issue's `blocks`, so it is read back off the card tree
  // -- including the nested children, in the order the tree walks them.
  function test_blocked_cards_are_read_off_the_nested_card_tree() {
    var data = exportData()
    var list = Extras.issueList(data, {})
    compare(list[0].id, "i3")
    compare(list[0].blocks.join(","), "c2,c3")
  }

  // `brd issue list` rows do carry `blocks`; those are honoured as they stand.
  function test_an_issue_row_that_carries_its_own_blocks_keeps_them() {
    var list = Extras.issueList({ issues: [{ id: "i9", blocks: ["c7", "c8"] }] }, {})
    compare(list[0].blocks.join(","), "c7,c8")
  }

  function test_issue_defaults_never_leak_undefined() {
    var list = Extras.issueList({ issues: [{ id: "i9" }, { title: "no id" }, null] }, {})
    compare(list.length, 1)
    compare(list[0].title, "i9")
    compare(list[0].status, "open")
    compare(list[0].body, "")
    compare(list[0].blocks.length, 0)
    compare(list[0].updatedAt, "")
  }

  function test_parse_export_reads_the_nested_v2_shape() {
    var result = Extras.parseExport(line(exportV2()), 0)
    compare(result.ok, true)
    compare(ids(result.issues), "i3,i1,i2")
    compare(result.issues[1].blocks.join(","), "c1", "blocks read back off the nested card tree")
    compare(result.commentsByEntity["c1"].length, 2)
    compare(result.refsByEntity["i1"].refs.join(","), "c1")
  }

  function test_flatten_export_concatenates_projects_and_tolerates_junk() {
    var v2 = exportV2()
    v2.projects.push({ project: {}, issues: [{ id: "x1", title: "X", status: "open" }] }, null)
    var flat = Extras.flattenExport(v2)
    compare(ids(flat.issues), "i1,i2,i3,x1")
    compare(flat.cards.length, 2)
    compare(Extras.flattenExport({ brd_export: 2, projects: [] }).issues.length, 0)
    compare(Extras.flattenExport(exportData()).brd_export, 1, "the flat shape passes through")
  }

  function test_parse_export_reads_one_line_and_drops_document_content() {
    var result = Extras.parseExport(line(exportData()), 0)
    compare(result.ok, true)
    compare(result.error, "")
    compare(ids(result.issues), "i3,i1,i2")
    compare(result.commentsByEntity["c1"].length, 2)
    compare(result.refsByEntity["i1"].refs.join(","), "c1")
    compare(Object.keys(result).sort().join(","), "commentsByEntity,error,issues,ok,refsByEntity",
            "the export's documents are never carried")
  }

  function test_a_failed_or_old_brd_parses_to_empty_extras() {
    var cases = [["", 0], ["Usage: brd [OPTIONS] COMMAND", 2],
                 ['{"ok": false, "error": {"type": "UsageError", "message": "no such command"}}', 2],
                 ["not json", 0], [null, 1]]
    for (var i = 0; i < cases.length; i++) {
      var result = Extras.parseExport(cases[i][0], cases[i][1])
      compare(result.ok, false, "case " + i)
      compare(result.issues.length, 0, "case " + i)
      compare(Object.keys(result.commentsByEntity).length, 0, "case " + i)
      compare(Object.keys(result.refsByEntity).length, 0, "case " + i)
    }
  }

  function test_filtering_searching_and_counting_issues() {
    var data = exportData()
    var list = Extras.issueList(data, {})
    compare(ids(Extras.filterIssues(list, "open")), "i3,i1")
    compare(ids(Extras.filterIssues(list, "closed")), "i2")
    compare(ids(Extras.filterIssues(list, "")), "i3,i1,i2")
    compare(ids(Extras.searchIssues(list, "broken")), "i1")
    compare(ids(Extras.searchIssues(list, "it fails")), "i1")
    compare(ids(Extras.searchIssues(list, "")), "i3,i1,i2")
    var counts = Extras.issueStatusCounts(list)
    compare(counts.map(function(c) { return c.id + ":" + c.count }).join(","), "open:2,closed:1")
    compare(Extras.issueStatusLabel("open"), "Open")
    compare(Extras.issueStatusLabel("nope"), "")
  }

  function test_issue_detail_links_list_only_reachable_targets() {
    var data = exportData()
    var list = Extras.issueList(data, {})
    var cardMap = { c1: { id: "c1", title: "Card One", status: "blocked" },
                    c2: { id: "c2", title: "Child", status: "blocked" } }
    var issueMap = { i1: { id: "i1", title: "Broken build", status: "open" } }
    var refs = Extras.indexRefs(data)
    var links = Extras.issueDetailLinks(list[1], cardMap, issueMap, refs)
    compare(links.map(function(l) { return l.section + ":" + l.id }).join(","),
            "blocks:c1,ref:c1,referenced_by:c1")
    compare(Extras.issueDetailLinks(list[0], cardMap, issueMap, refs)
              .map(function(l) { return l.id }).join(","), "c2", "a blocked id not in the board is left out")
    compare(Extras.issueDetailLinks(null, cardMap, issueMap, refs).length, 0)
  }

  function test_the_wording_helpers() {
    compare(Extras.blocksLabel(0), "")
    compare(Extras.blocksLabel(1), "blocks 1 card")
    compare(Extras.blocksLabel(3), "blocks 3 cards")
    compare(Extras.commentCountLabel(0), "")
    compare(Extras.commentCountLabel(1), "1 comment")
    compare(Extras.commentCountLabel(4), "4 comments")
  }

  function test_relative_time_falls_back_to_the_raw_text() {
    var now = Date.parse("2026-09-24T12:00:00+00:00")
    compare(Extras.relativeTime("2026-09-24T11:59:30+00:00", now), "just now")
    compare(Extras.relativeTime("2026-09-24T11:30:00+00:00", now), "30m ago")
    compare(Extras.relativeTime("2026-09-24T09:00:00+00:00", now), "3h ago")
    compare(Extras.relativeTime("2026-09-22T12:00:00+00:00", now), "2d ago")
    compare(Extras.relativeTime("2026-08-01T12:00:00+00:00", now), "2026-08-01")
    compare(Extras.relativeTime("not a date", now), "not a date")
    compare(Extras.relativeTime("", now), "")
    compare(Extras.relativeTime(undefined, now), "")
  }

  // `brd doc list` -- note source_path is relative to the project root. The
  // second row is a defensive shape: a brd that stops sending some field must
  // not leave the listing with undefined in it.
  property string docListLine: JSON.stringify({ ok: true, data: [
    { id: "d1", kind: "document", title: "Design", source_path: "docs/a.md", source_state: "ok",
      tags: ["design", "brd"], created_at: "2026-09-20T10:00:00+00:00", updated_at: "2026-09-24T10:00:00+00:00" },
    { id: "d2", kind: "document", title: "Gone", source_path: "notes/b.md", source_state: "missing", tags: [] }] })

  function test_the_document_listing_is_parsed() {
    var result = Extras.parseDocList(docListLine, 0)
    compare(result.ok, true)
    compare(result.registered.length, 2)
    compare(result.registered[0].sourcePath, "docs/a.md")
    compare(result.registered[0].sourceState, "ok")
    compare(result.registered[0].tags.join(","), "design,brd")
    compare(result.registered[1].sourceState, "missing")
    compare(result.registered[1].tags.length, 0)
  }

  function test_a_failed_document_listing_is_empty_and_never_throws() {
    var bad = Extras.parseDocList('{"ok": false, "error": {"type": "X", "message": "nope"}}', 2)
    compare(bad.ok, false)
    compare(bad.registered.length, 0)
    compare(Extras.parseDocList("garbage", 0).registered.length, 0)
    compare(Extras.parseDocList("", 1).registered.length, 0)
  }

  // A registered source_path is joined onto the project root to open the file,
  // so a path that escapes the project (absolute, or with a `..` segment) is
  // dropped: it is not a document of this project and must never be opened.
  function test_a_source_path_that_escapes_the_project_is_dropped() {
    var line = JSON.stringify({ ok: true, data: [
      { id: "d1", title: "Fine", source_path: "docs/a.md", source_state: "ok", tags: [] },
      { id: "d2", title: "Escape", source_path: "../../etc/passwd", source_state: "ok", tags: [] },
      { id: "d3", title: "Absolute", source_path: "/etc/passwd", source_state: "ok", tags: [] },
      { id: "d4", title: "Hidden", source_path: "docs/../../etc/passwd", source_state: "ok", tags: [] },
      { id: "d5", title: "Backslash", source_path: "docs\\..\\..\\etc\\passwd", source_state: "ok", tags: [] },
      { id: "d6", title: "Dotted", source_path: "docs/..hidden.md", source_state: "ok", tags: [] }] })
    var result = Extras.parseDocList(line, 0)
    compare(result.ok, true)
    compare(result.registered.map(function(d) { return d.id }).join(","), "d1,d6",
            "only the paths that stay inside the project survive")
  }
}
