const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "kcov",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "src/capabilities.cc",
            "src/collector.cc",
            "src/configuration.cc",
            // "src/dummy-solib-handler.cc",
            "src/engine-factory.cc",
            "src/engines/bash-engine.cc",
            "src/engines/clang-coverage-engine.cc",
            // "src/engines/gcov-engine.cc",
            // "src/engines/kernel-engine.cc",
            // "src/engines/mach-engine.cc",
            // "src/engines/ptrace_freebsd.cc",
            "src/engines/ptrace_linux.cc",
            "src/engines/ptrace.cc",
            "src/engines/python-engine.cc",
            "src/engines/system-mode-binary-lib.cc",
            "src/engines/system-mode-engine.cc",
            "src/engines/system-mode-file-format.cc",
            "src/filter.cc",
            "src/gcov.cc",
            // "src/main-system-daemon.cc",
            "src/main.cc",
            "src/merge-file-parser.cc",
            "src/output-handler.cc",
            "src/parser-manager.cc",
            // "src/parsers/bfd-disassembler.cc",
            "src/parsers/dummy-disassembler.cc",
            // "src/parsers/dwarf-libdwarf.cc",
            "src/parsers/dwarf.cc",
            "src/parsers/elf-parser.cc",
            "src/parsers/elf.cc",
            // "src/parsers/macho-parser.cc",
            "src/reporter.cc",
            "src/solib-handler.cc",
            "src/source-file-cache.cc",
            "src/system-mode/file-data.cc",
            "src/system-mode/registration.cc",
            "src/utils.cc",
            "src/writers/cobertura-writer.cc",
            "src/writers/codecov-writer.cc",
            "src/writers/coveralls-writer.cc",
            // "src/writers/dummy-coveralls-writer.cc",
            "src/writers/html-writer.cc",
            "src/writers/json-writer.cc",
            "src/writers/sonarqube-xml-writer.cc",
            "src/writers/writer-base.cc",
            "src/solib-parser/phdr_data.c",
            "src/solib-parser/lib.c",
            // "src/kernel/kprobe-coverage.c",
            "src/engines/bash-tracefd-cloexec.c",
            "src/engines/bash-execve-redirector.c",
            // "src/engines/osx/mach_excServer.c",
            "version.c",
        },
    });
    inline for (datasets) |set| {
        const cmd = b.addSystemCommand(set.cmd);
        const w = b.addWriteFiles();
        exe.addCSourceFile(.{
            .file = w.addCopyFile(cmd.captureStdOut(), set.name),
        });
    }
    // exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("curl");
    exe.linkSystemLibrary("elf");
    exe.linkSystemLibrary("dw");
    exe.linkSystemLibrary("z");
    // exe.linkSystemLibrary("elfutils");
    exe.linkSystemLibrary("dwarf");
    exe.addSystemIncludePath(.{ .path = "/usr/include/libdwarf" });
    // exe.addSystemIncludePath(.{.path="/usr/include"});
    exe.defineCMacro("NDEBUG", "1");
    // exe.linkSystemLibrary("istringstream");
    exe.addIncludePath(.{ .path = "src/include" });

    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("run", "Run KCOV").dependOn(&run.step);
}

const datasets = .{
    .{
        .name = "bash-redirector-library.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "build.zig", // TODO: compile the actual $<TARGET_FILE:bash_execve_redirector>
            "bash_redirector_library",
        },
    },
    .{
        .name = "library.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "build.zig", // TODO: compile the actual $<TARGET_FILE:${SOLIB}>
            "__library",
        },
    },
    .{
        .name = "kcov-system-library.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "build.zig", // TODO: compile the actual $<TARGET_FILE:kcov_system_lib>
            "kcov_system_library",
        },
    },
    .{
        .name = "python-helper.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "src/engines/python-helper.py",
            "python_helper",
        },
    },
    .{
        .name = "bash-helper.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "src/engines/bash-helper.sh",
            "bash_helper",
            "src/engines/bash-helper-debug-trap.sh",
            "bash_helper_debug_trap",
        },
    },
    .{
        .name = "bash-cloexec-library.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "build.zig", // TODO: build $<TARGET_FILE:bash_tracefd_cloexec>
            "bash_cloexec_library",
        },
    },
    .{
        .name = "html-data-files.cc",
        .cmd = &[_][]const u8{
            "./src/bin-to-c-source.py",
            "data/bcov.css",
            "css_text",
            "data/amber.png",
            "icon_amber",
            "data/glass.png",
            "icon_glass",
            "data/source-file.html",
            "source_file_text",
            "data/index.html",
            "index_text",
            "data/js/handlebars.js",
            "handlebars_text",
            "data/js/kcov.js",
            "kcov_text",
            "data/js/jquery.min.js",
            "jquery_text",
            "data/js/jquery.tablesorter.min.js",
            "tablesorter_text",
            "data/js/jquery.tablesorter.widgets.min.js",
            "tablesorter_widgets_text",
            "data/tablesorter-theme.css",
            "tablesorter_theme_text",
        },
    },
};
