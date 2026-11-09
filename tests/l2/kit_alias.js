/**
 * 智寓 · L2 模块别名（把 `@kit.*` 指到 `tests/l2/stubs/` 编译产物，**仅测试用**）
 *
 * 为什么需要：`gen.js` + `tsconfig.json` 只在**类型层**把 `@kit.ArkData` 等模块名映射到桩文件
 * （`compilerOptions.paths`），tsc **不会**改写产物里的 `require("@kit.ArkData")` 说明符。
 * Node 侧没有鸿蒙运行时，直接 require 必然 `MODULE_NOT_FOUND`，所以在加载被测模块前
 * 挂一个解析钩子，把这 4 个说明符改指 `.gen/out/__stub/*.js`。
 *
 * ★ 只在测试进程内生效，不影响 HAP；也不要放进 `entry/` 下任何位置。
 */
'use strict';

const path = require('path');
const Module = require('module');

const STUB_OUT = path.join(__dirname, '.gen', 'out', '__stub');

const ALIAS = {
  '@kit.ArkData': path.join(STUB_OUT, 'kit_arkdata.js'),
  '@kit.AbilityKit': path.join(STUB_OUT, 'kit_abilitykit.js'),
  '@kit.BasicServicesKit': path.join(STUB_OUT, 'kit_basicservices.js'),
  '@kit.ArkTS': path.join(STUB_OUT, 'kit_arkts.js')
};

const originalResolve = Module._resolveFilename;

Module._resolveFilename = function (request, parent, isMain, options) {
  if (Object.prototype.hasOwnProperty.call(ALIAS, request)) {
    return ALIAS[request];
  }
  return originalResolve.call(this, request, parent, isMain, options);
};
