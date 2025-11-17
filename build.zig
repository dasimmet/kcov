const std = @import("std");

const version = std.SemanticVersion.parse(@import("build.zig.zon").version) catch unreachable;

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("kcov", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const system_daemon = b.option(bool, "system-daemon", "Enable support for full system instrumentation (untested)") orelse false;

    const link_system_zlib = b.systemIntegrationOption("zlib", .{});
    const link_system_binutils = b.systemIntegrationOption("binutils", .{});
    const link_system_elfutils = b.systemIntegrationOption("elfutils", .{});
    const link_system_curl = b.systemIntegrationOption("curl", .{});
    const use_system_dwarfutils = b.systemIntegrationOption("dwarfutils", .{});

    const kcov_sowrapper = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "kcov_sowrapper",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    kcov_sowrapper.root_module.addIncludePath(upstream.path("src/include"));
    kcov_sowrapper.root_module.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = &.{
            "src/solib-parser/phdr_data.c",
            "src/solib-parser/lib.c",
        },
    });

    const bash_execve_redirector = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "bash_execve_redirector",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    bash_execve_redirector.root_module.addCSourceFile(.{ .file = upstream.path("src/engines/bash-execve-redirector.c") });

    const bash_tracefd_cloexec = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "bash_tracefd_cloexec",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    bash_tracefd_cloexec.root_module.addCSourceFile(.{ .file = upstream.path("src/engines/bash-tracefd-cloexec.c") });

    const kcov_system_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "kcov_system_lib",
        .root_module = b.createModule(.{
            .root_source_file = b.addWriteFiles().add("empty.zig", ""),
            .target = target,
            .optimize = optimize,
        }),
    });

    // TODO fix kcov_system_lib compiling a static executable
    // const kcov_system_lib = b.addLibrary(.{
    //     .linkage = .dynamic,
    //     .name = "kcov_system_lib",
    //     .root_module = b.createModule(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .link_libc = true,
    //         .link_libcpp = true,
    //     }),
    // });
    // kcov_system_lib.root_module.addIncludePath(upstream.path("src/include"));
    // kcov_system_lib.root_module.addCSourceFiles(.{
    //     .root = upstream.path("."),
    //     .files = &.{
    //         "src/engines/system-mode-binary-lib.cc",
    //         "src/utils.cc",
    //         "src/system-mode/registration.cc",
    //     },
    // });

    // TODO utilize C23 #embed
    const bin_to_c_source = b.addExecutable(.{
        .name = "bin_to_c_source",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin_to_c_source.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const library_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.addArtifactArg(kcov_sowrapper);
        run_bin_to_c_source.addArg("__library");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "library.cc");
    };

    const bash_redirector_library_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.addArtifactArg(bash_execve_redirector);
        run_bin_to_c_source.addArg("bash_redirector_library");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "bash-redirector-library.cc");
    };

    const bash_cloexec_library_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.addArtifactArg(bash_tracefd_cloexec);
        run_bin_to_c_source.addArg("bash_cloexec_library");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "bash-cloexec-library.cc");
    };

    const kcov_system_library_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.max_stdio_size = 256 * 1024 * 1024; // 256MiB
        run_bin_to_c_source.addArtifactArg(kcov_system_lib);
        run_bin_to_c_source.addArg("kcov_system_library");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "kcov-system-library.cc");
    };

    const python_helper_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.addFileArg(upstream.path("src/engines/python-helper.py"));
        run_bin_to_c_source.addArg("python_helper");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "python-helper.cc");
    };

    const bash_helper_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.addFileArg(upstream.path("src/engines/bash-helper.sh"));
        run_bin_to_c_source.addArg("bash_helper");
        run_bin_to_c_source.addFileArg(upstream.path("src/engines/bash-helper-debug-trap.sh"));
        run_bin_to_c_source.addArg("bash_helper_debug_trap");
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "bash-helper.cc");
    };

    const html_data_files_cc = blk: {
        const run_bin_to_c_source = b.addRunArtifact(bin_to_c_source);
        run_bin_to_c_source.clearEnvironment();
        run_bin_to_c_source.max_stdio_size = 32 * 1024 * 1024; // 32MiB
        for (
            [_][]const u8{
                "data/bcov.css",
                "data/amber.png",
                "data/glass.png",
                "data/source-file.html",
                "data/index.html",
                "data/js/handlebars.js",
                "data/js/kcov.js",
                "data/js/jquery.min.js",
                "data/js/jquery.tablesorter.min.js",
                "data/js/jquery.tablesorter.widgets.min.js",
                "data/tablesorter-theme.css",
            },
            [_][]const u8{
                "css_text",
                "icon_amber",
                "icon_glass",
                "source_file_text",
                "index_text",
                "handlebars_text",
                "kcov_text",
                "jquery_text",
                "tablesorter_text",
                "tablesorter_widgets_text",
                "tablesorter_theme_text",
            },
        ) |path, name| {
            run_bin_to_c_source.addFileArg(upstream.path(path));
            run_bin_to_c_source.addArg(name);
        }
        break :blk renameLazyPath(b, run_bin_to_c_source.captureStdOut(), "html-data-files.cc");
    };

    const version_c = blk: {
        const write_files = b.addWriteFiles();
        break :blk write_files.add("version.c", b.fmt("const char *kcov_version = \"{f}\";", .{version}));
    };

    const kcov = b.addExecutable(.{
        .name = "kcov",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .pic = true,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    b.installArtifact(kcov);
    kcov.root_module.addIncludePath(upstream.path("src/include"));
    kcov.root_module.addCMacro("KCOV_LIBRARY_PREFIX", "/tmp");

    kcov.root_module.addCSourceFile(.{ .file = bash_redirector_library_cc });
    kcov.root_module.addCSourceFile(.{ .file = bash_cloexec_library_cc });
    kcov.root_module.addCSourceFile(.{ .file = python_helper_cc });
    kcov.root_module.addCSourceFile(.{ .file = bash_helper_cc });
    kcov.root_module.addCSourceFile(.{ .file = kcov_system_library_cc });
    kcov.root_module.addCSourceFile(.{ .file = html_data_files_cc });
    kcov.root_module.addCSourceFile(.{ .file = version_c });

    // TODO test Coveralls support
    kcov.root_module.addCSourceFile(.{ .file = upstream.path("src/writers/coveralls-writer.cc") });
    // kcov.root_module.addCSourceFile(.{ .file = upstream.path("src/writers/dummy-coveralls-writer.cc") });

    if (target.result.cpu.arch.isX86()) {
        if (link_system_binutils) {
            kcov.root_module.linkSystemLibrary("bfd", .{});
            kcov.root_module.linkSystemLibrary("opcodes", .{});
        } else if (b.lazyDependency("binutils", .{
            .target = target,
            .optimize = optimize,
        })) |binutils_dependency| {
            kcov.root_module.linkLibrary(binutils_dependency.artifact("bfd"));
            kcov.root_module.linkLibrary(binutils_dependency.artifact("opcodes"));
        }
        kcov.root_module.addCSourceFile(.{ .file = upstream.path("src/parsers/bfd-disassembler.cc") });
        kcov.root_module.addCMacro("ATTRIBUTE_FPTR_PRINTF_2", "ATTRIBUTE_FPTR_PRINTF(2, 3)");
        kcov.root_module.addCMacro("KCOV_HAS_LIBBFD", "1");
        kcov.root_module.addCMacro("KCOV_LIBFD_DISASM_STYLED", "1"); // TODO?
        kcov.root_module.addCMacro("PACKAGE", "1");
        kcov.root_module.addCMacro("PACKAGE_VERSION", "1");
    } else {
        kcov.root_module.addCSourceFile(.{ .file = upstream.path("src/parsers/dummy-disassembler.cc") });
        kcov.root_module.addCMacro("KCOV_HAS_LIBBFD", "0");
        kcov.root_module.addCMacro("KCOV_LIBFD_DISASM_STYLED", "0");
    }

    kcov.root_module.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "capabilities.cc",
            "collector.cc",
            "configuration.cc",
            "engine-factory.cc",
            "engines/bash-engine.cc",
            "engines/system-mode-engine.cc",
            "engines/system-mode-file-format.cc",
            "engines/python-engine.cc",
            "filter.cc",
            "main.cc",
            "merge-file-parser.cc",
            "output-handler.cc",
            "parser-manager.cc",
            "reporter.cc",
            "source-file-cache.cc",
            "utils.cc",
            "writers/cobertura-writer.cc",
            "writers/codecov-writer.cc",
            "writers/json-writer.cc",
            "writers/html-writer.cc",
            "writers/sonarqube-xml-writer.cc",
            "writers/writer-base.cc",
            "system-mode/file-data.cc",
        },
    });

    switch (target.result.os.tag) {
        .linux, .freebsd => |os_tag| {
            // ELF_SRCS
            kcov.root_module.addCSourceFiles(.{
                .root = upstream.path("."),
                .files = &.{
                    "src/engines/ptrace.cc",
                    if (os_tag == .linux)
                        "src/engines/ptrace_linux.cc"
                    else
                        "src/engines/ptrace_freebsd.cc",
                    "src/parsers/elf.cc",
                    "src/parsers/elf-parser.cc",
                    "src/parsers/dwarf.cc",
                    "src/solib-handler.cc",
                    "src/solib-parser/phdr_data.c",
                },
            });
            if (os_tag == .linux) {
                kcov.root_module.addCSourceFile(.{ .file = upstream.path("src/engines/kernel-engine.cc") });
            }

            // SOLIB_generated
            kcov.root_module.addCSourceFile(.{ .file = library_cc });
        },
        .ios,
        .macos,
        .watchos,
        .tvos,
        => {
            // ELF_SRCS
            kcov.addCSourceFile(.{ .file = upstream.path("src/dummy-solib-handler.cc") });

            // MACHO_SRCS
            kcov.addCSourceFiles(.{
                .root = upstream.path("."),
                .files = &.{
                    "src/parsers/macho-parser.cc",
                    "src/engines/mach-engine.cc",
                    "src/engines/osx/mach_excServer.c",
                },
            });
        },
        else => |os_tag| std.debug.panic("unsupported os '{s}'", .{@tagName(os_tag)}),
    }

    var kcov_system_daemon: ?*std.Build.Step.Compile = null;

    if (target.result.os.tag == .linux) {
        const system_daemon = b.addExecutable(.{
            .name = "kcov-system-daemon",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .link_libcpp = true,
            }),
        });
        b.installArtifact(system_daemon);
        system_daemon.root_module.addIncludePath(upstream.path("src/include"));
        system_daemon.root_module.addCSourceFile(.{ .file = version_c });
        system_daemon.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{
                "configuration.cc",
                "dummy-solib-handler.cc",
                "engine-factory.cc",
                "engines/system-mode-file-format.cc",
                "engines/ptrace.cc",
                "engines/ptrace_linux.cc",
                "filter.cc",
                "main-system-daemon.cc",
                "parser-manager.cc",
                "system-mode/file-data.cc",
                "system-mode/registration.cc",
                "utils.cc",
            },
        });

        kcov_system_daemon = system_daemon;
    }

    const run_kcov = b.addRunArtifact(kcov);
    run_kcov.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_kcov.addArgs(args);
    }

    const run_step = b.step("run", "Run kcov");
    run_step.dependOn(&run_kcov.step);

    const line2addr = b.addExecutable(.{
        .name = "line2addr",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    line2addr.root_module.addIncludePath(upstream.path("src/include"));
    line2addr.root_module.addCSourceFile(.{ .file = upstream.path("tools/line2addr.cc") });
    line2addr.root_module.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &.{
            "capabilities.cc",
            "configuration.cc",
            "filter.cc",
            "parsers/dwarf.cc",
            "parsers/elf-parser.cc",
            "parsers/elf.cc",
            "parsers/dummy-disassembler.cc",
            "parser-manager.cc",
            "utils.cc",
        },
    });

    const run_line2addr = b.addRunArtifact(kcov);

    if (b.args) |args| {
        run_line2addr.addArgs(args);
    }

    const line2addr_step = b.step("line2addr", "Run line2addr");
    line2addr_step.dependOn(&run_line2addr.step);

    if (link_system_curl) {
        kcov.root_module.linkSystemLibrary("curl", .{});
        if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkSystemLibrary("curl", .{});
        line2addr.root_module.linkSystemLibrary("curl", .{});
    } else if (b.lazyDependency("curl", .{
        .target = target,
        .optimize = optimize,

        // allyourcodebase/openssl only works on x86_64-linux
        .@"use-mbedtls" = true,

        // These dependencies would require linking system libraries
        .nghttp2 = false,
        .libidn2 = false,
        .libpsl = false,
        .libssh2 = false,
        .@"disable-ldap" = true,
    })) |curl_dependency| {
        if (b.lazyImport(@This(), "curl")) |curl_builder| {
            // https://github.com/ziglang/zig/issues/20377
            const libCurl = curl_builder.artifact(curl_dependency, .lib);
            kcov.root_module.linkLibrary(libCurl);
            if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkLibrary(libCurl);
            line2addr.root_module.linkLibrary(libCurl);
        }
    }

    if (link_system_zlib) {
        kcov.root_module.linkSystemLibrary("z", .{});
        if (kcov_system_daemon) |system_daemon| system_daemon.linkSystemLibrary("z");
        line2addr.root_module.linkSystemLibrary("z", .{});
    } else if (b.lazyDependency("zlib", .{
        .target = target,
        .optimize = optimize,
    })) |zlib_dependency| {
        kcov.root_module.linkLibrary(zlib_dependency.artifact("z"));
        if (kcov_system_daemon) |system_daemon| system_daemon.linkLibrary(zlib_dependency.artifact("z"));
        line2addr.root_module.linkLibrary(zlib_dependency.artifact("z"));
    }

    if (target.result.os.tag == .linux) {
        if (link_system_elfutils) {
            kcov.root_module.linkSystemLibrary("elf", .{});
            kcov.root_module.linkSystemLibrary("dw", .{});
            if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkSystemLibrary("elf", .{});
            if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkSystemLibrary("dw", .{});
            line2addr.root_module.linkSystemLibrary("elf", .{});
            line2addr.root_module.linkSystemLibrary("dw", .{});
        } else if (b.lazyDependency("elfutils", .{
            .target = target,
            .optimize = optimize,
        })) |elfutils_dependency| {
            kcov.root_module.linkLibrary(elfutils_dependency.artifact("elf"));
            kcov.root_module.linkLibrary(elfutils_dependency.artifact("dw"));
            if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkLibrary(elfutils_dependency.artifact("elf"));
            if (kcov_system_daemon) |system_daemon| system_daemon.root_module.linkLibrary(elfutils_dependency.artifact("dw"));
            line2addr.root_module.linkLibrary(elfutils_dependency.artifact("elf"));
            line2addr.root_module.linkLibrary(elfutils_dependency.artifact("dw"));
        }
    } else if (target.result.os.tag.isDarwin()) {
        if (use_system_dwarfutils) {
            kcov.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/local/opt/dwarfutils/include/libdwarf-0/" });
            kcov.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/dwarfutils/include/libdwarf-0/" });
            kcov.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/opt/dwarfutils/lib/" });
            kcov.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/dwarfutils/lib/" });
            kcov.root_module.linkSystemLibrary("dwarf", .{});
        } else {
            // TODO https://www.prevanders.net/dwarf.html
        }
    }
}

fn renameLazyPath(b: *std.Build, lazy_path: std.Build.LazyPath, basename: []const u8) std.Build.LazyPath {
    const write_files = b.addWriteFiles();
    return write_files.addCopyFile(lazy_path, basename);
}
