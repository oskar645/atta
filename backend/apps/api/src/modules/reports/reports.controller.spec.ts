import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { METHOD_METADATA, PATH_METADATA } from '@nestjs/common/constants';
import { RequestMethod } from '@nestjs/common';

import { AdminReportsController } from './reports.controller';

test('AdminReportsController keeps paginated admin reports endpoint', () => {
  assert.equal(
    Reflect.getMetadata(PATH_METADATA, AdminReportsController),
    'admin/reports',
  );

  const descriptor = Object.getOwnPropertyDescriptor(
    AdminReportsController.prototype,
    'list',
  );
  assert.ok(descriptor?.value);
  assert.equal(Reflect.getMetadata(PATH_METADATA, descriptor.value), '/');
  assert.equal(
    Reflect.getMetadata(METHOD_METADATA, descriptor.value),
    RequestMethod.GET,
  );
});

test('AdminReportsController forwards pagination query to service', () => {
  const calls: unknown[] = [];
  const controller = new AdminReportsController({
    listForAdmin: (query: unknown) => {
      calls.push(query);
      return {
        items: [],
        nextCursor: null,
        hasMore: false,
      };
    },
  } as never);

  const query = {
    limit: 25,
    cursor: 'cursor-1',
  };
  const result = controller.list(query);

  assert.deepEqual(calls, [query]);
  assert.deepEqual(result, {
    items: [],
    nextCursor: null,
    hasMore: false,
  });
});
