# encoding: utf-8
# Copyright 2014 Aerospike, Inc.
#
# Portions may be licensed to Aerospike, Inc. under one or more contributor
# license agreements.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require "spec_helper"

require 'aerospike/host'
require 'aerospike/key'
require 'aerospike/bin'

require 'benchmark'

describe Aerospike::Client do

  let(:client) { Support.client }

  describe "#initialize" do

    around(:each) do |example|
      begin
        as_hosts = ENV.delete("AEROSPIKE_HOSTS")
        example.call
      ensure
        ENV["AEROSPIKE_HOSTS"] = as_hosts
      end
    end

    def cluster_seeds(client)
      client.instance_variable_get(:@cluster).seeds
    end

    it "accepts a single Host" do
      host = Aerospike::Host.new("10.10.10.10", 3333)
      client = Aerospike::Client.new(host, connect: false)

      expect(cluster_seeds(client)).to eq [host]
    end

    it "accepts a list of Hosts" do
      host1 = Aerospike::Host.new("10.10.10.10", 3333)
      host2 = Aerospike::Host.new("10.10.10.11", 3333)
      client = Aerospike::Client.new([host1, host2], connect: false)

      expect(cluster_seeds(client)).to eq [host1, host2]
    end

    it "accepts a single hostname" do
      client = Aerospike::Client.new("10.10.10.10", connect: false)

      expect(cluster_seeds(client)).to eq [Aerospike::Host.new("10.10.10.10", 3000)]
    end

    it "accepts a single hostname and port" do
      client = Aerospike::Client.new("10.10.10.10:3333", connect: false)

      expect(cluster_seeds(client)).to eq [Aerospike::Host.new("10.10.10.10", 3333)]
    end

    it "accepts a list of hostnames" do
      client = Aerospike::Client.new("10.10.10.10:3333,10.10.10.11", connect: false)

      expect(cluster_seeds(client)).to eq [Aerospike::Host.new("10.10.10.10", 3333), Aerospike::Host.new("10.10.10.11", 3000)]
    end

    it "reads a list of hostnames from AEROSPIKE_HOSTS" do
      ENV["AEROSPIKE_HOSTS"] = "10.10.10.10:3333,10.10.10.11"
      client = Aerospike::Client.new(connect: false)

      expect(cluster_seeds(client)).to eq [Aerospike::Host.new("10.10.10.10", 3333), Aerospike::Host.new("10.10.10.11", 3000)]
    end

    it "defaults to localhost:3000" do
      ENV["AEROSPIKE_HOSTS"] = nil
      client = Aerospike::Client.new(connect: false)

      expect(cluster_seeds(client)).to eq [Aerospike::Host.new("localhost", 3000)]
    end

  end

  describe "#connect" do
    let(:client_policy) { Hash.new }
    let(:client) { described_class.new(policy: client_policy, connect: false) }

    it "should connect to the cluster successfully" do
      client.connect
      expect(client.connected?).to eq true
    end

    it "should have at least one node" do
      client.connect
      expect(client.nodes.length).to be >= 1
    end

    it "should have at least one name in node name list" do
      client.connect
      expect(client.node_names.length).to be >= 1
    end

    context "with non-matching cluster name" do
      let(:client_policy) { { cluster_name: 'thisIsNotTheRealClusterName' } }

      it "should fail to connect if the cluster name does not match" do
        expect { client.connect }.to raise_error(Aerospike::Exceptions::Aerospike)
      end
    end
  end

  describe "#put and #get" do

    context "data types" do

      it "should put a hash with bins and get it back successfully" do

        key = Support.gen_random_key

        bin_map = {
          'bin1' => 'value1',
          'bin2' => 2,
          'bin4' => ['value4', {'map1' => 'map val'}],
          'bin5' => {'value5' => [124, "string value"]},
        }

        client.put(key, bin_map)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins).to eq bin_map

      end

      it "should put a hash with bins and get only some bins" do

        key = Support.gen_random_key

        bin_map = {
          'bin1' => 'value1',
          'bin2' => 2,
          'bin4' => ['value4', {'map1' => 'map val'}],
          'bin5' => {'value5' => [124, "string value"]},
        }

        client.put(key, bin_map)

        expect(client.connected?).to eq true

        record = client.get(key, ['bin1', 'bin2'])
        expect(record.bins).to eq ({'bin1' => 'value1', 'bin2' => 2})

      end

      it "should put a STRING and get it successfully" do

        key = Support.gen_random_key
        client.put(key, Aerospike::Bin.new('bin', 'value'))

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq 'value'

      end

      it "should put a STRING with non-ASCII characters and get it successfully" do

        key = Support.gen_random_key
        client.put(key, Aerospike::Bin.new('bin', '柑橘類の葉'))

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq '柑橘類の葉'

      end

      it "should put a NIL and get it successfully" do

        key = Support.gen_random_key
        client.put(key, [Aerospike::Bin.new('bin', nil),
                         Aerospike::Bin.new('bin1', 'auxilary')]
                   )

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq nil

      end

      it "should put an INTEGER and get it successfully" do

        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', rand(2**63))
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value

      end

      it "should put a FLOAT and get it successfully" do

        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', rand)
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value

      end

      it "should put a GeoJSON value and get it successfully", skip: !Support.feature?('geo') do
        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', Aerospike::GeoJSON.new({type: "Point", coordinates: [103.9114, 1.3083]}))
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value

      end

      it "should put an ARRAY and get it successfully" do

        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', [
                                   "string",
                                   rand(2**63),
                                   [1, nil, 'this'],
                                   ["embedded array", 1984, nil, {2 => 'string'}],
                                   nil,
                                   {'array' => ["another string", 17]},
        ])
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value

      end

      it "should put a MAP and get it successfully" do

        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', {
                                   "string" => nil,
                                   rand(2**63) => {2 => 11},
                                   [1, nil, 'this'] => {nil => "nihilism"},
                                   nil => ["embedded array", 1984, nil, {2 => 'string'}],
                                   {11 => [11, 'str']} => nil,
                                   {} => {'array' => ["another string", 17]},
        })
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value

      end

      it "should write a key as symbol successfully and get it well, even as text" do
        key = Support.gen_random_key
        bin = Aerospike::Bin.new('bin', {
                                   "string" => nil,
                                   rand(2**63) => {2 => 11},
                                   [1, nil, 'this'] => {nil => "nihilism"},
                                   nil => ["embedded array", 1984, nil, {2 => 'string'}],
                                   {11 => [11, 'str']} => nil,
                                   {} => {'array' => ["another string", 17]},
        })
        client.put(key, bin)

        expect(client.connected?).to eq true

        record = client.get(key)
        expect(record.bins['bin']).to eq bin.value
      end

    end

    it "should write a key as symbol successfully - and read its header again. It should behave like a String" do
      key = Support.gen_random_key(50, :key_as_sym => true)

      expect(key.user_key.is_a?(String))

      client.put(key, Aerospike::Bin.new('bin', 'value'))

      expect(client.connected?).to eq true

      record = client.get_header(key)
      expect(record.bins).to be nil
      expect(record.generation).to eq 1
      expect(record.expiration).to be > 0
    end

    it "should raise an error if hash with non-string keys is passed as record" do
      key = Support.gen_random_key

      expect { client.put(key, {symbol_key: "string value"}) }.to raise_error(Aerospike::Exceptions::Aerospike)
    end

  end

  describe "#put and #delete" do

    it "should write a key successfully - and delete it" do

      key = Support.gen_random_key
      client.put(key, Aerospike::Bin.new('bin', 'value'))

      existed = client.delete(key)
      expect(existed).to eq true

    end

    it "should return existed = false on non-existing keys" do

      key = Support.gen_random_key
      existed = client.delete(key)
      expect(existed).to eq false

    end

    it "should apply durable delete policy", skip: !Support.min_version?("3.10") do
      key = Support.gen_random_key
      if Support.enterprise?
        expect { client.delete(key, durable_delete: true) }.to_not raise_exception
      else
        expect { client.delete(key, durable_delete: true) }.to raise_exception(/enterprise-only/i)
      end
    end

  end

  describe "#put and #touch" do

    it "should write a key successfully - and touch it to bump generation" do

      key = Support.gen_random_key
      client.put(key, Aerospike::Bin.new('bin', 'value'))

      client.touch(key)
      record = client.get_header(key)
      expect(record.generation).to eq 2

    end

  end

  describe "#put and #exists" do

    it "should write a key successfully - and check if it exists" do

      key = Support.gen_random_key

      exists = client.exists(key)
      expect(exists).to eq false

      client.put(key, Aerospike::Bin.new('bin', 'value'))

      exists = client.exists(key)
      expect(exists).to eq true

    end

  end

  describe "#put and change" do

    let(:key) do
      Support.gen_random_key
    end

    before do

      exists = client.exists(key)
      expect(exists).to eq false

      client.put(key, {'str' => 'value', 'int' => 10, 'float' => 3.14159})

      exists = client.exists(key)
      expect(exists).to eq true
    end

    it "should append to a key successfully" do

      client.append(key, {'str' => '1' })
      record = client.get(key)
      expect(record.bins['str']).to eq 'value1'

    end

    it "should prepend to a key successfully" do

      client.prepend(key, {'str' => '0' })
      record = client.get(key)
      expect(record.bins['str']).to eq '0value'

    end

    it "should add to an int key successfully" do

      client.add(key, {'int' => 10 })
      record = client.get(key)
      expect(record.bins['int']).to eq 20

      client.add(key, {'int' => -10 })
      record = client.get(key)
      expect(record.bins['int']).to eq 10

    end

    it "should add to a float key successfully" do

      client.add(key, {'float' => 2.71828 })
      record = client.get(key)
      expect(record.bins['float']).to eq 5.85987

      client.add(key, {'float' => -3.14159 })
      record = client.get(key)
      expect(record.bins['float']).to eq 2.71828

    end

  end

  describe "#operate" do

    let(:key) do
      Support.gen_random_key
    end

    let(:bin_str) do
      Aerospike::Bin.new('bin name', 'string')
    end

    let(:bin_int) do
      Aerospike::Bin.new('bin name', rand(456123890))
    end

    let(:bin_float) do
      Aerospike::Bin.new('bin name', rand)
    end

    it "should #add, #get" do
      client.operate(key, [
                       Aerospike::Operation.add(bin_int),
      ])
      rec = client.get(key)
      expect(rec.bins[bin_str.name]).to eq bin_int.value * 1
      expect(rec.generation).to eq 1
    end

    it "should #put, #append" do

      rec = client.operate(key, [
                             Aerospike::Operation.put(bin_str),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to eq bin_str.value
      expect(rec.generation).to eq 1

      rec = client.operate(key, [
                             Aerospike::Operation.append(bin_str),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to eq bin_str.value * 2
      expect(rec.generation).to eq 2

    end

    it "should #put, #prepend" do

      rec = client.operate(key, [
                             Aerospike::Operation.put(bin_str),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to eq bin_str.value
      expect(rec.generation).to eq 1

      rec = client.operate(key, [
                             Aerospike::Operation.prepend(bin_str),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to eq bin_str.value * 2
      expect(rec.generation).to eq 2
    end

    it "should #put, #add integer" do

      rec = client.operate(key, [
                             Aerospike::Operation.put(bin_int),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_int.name]).to eq bin_int.value
      expect(rec.generation).to eq 1

      rec = client.operate(key, [
                             Aerospike::Operation.add(bin_int),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to eq bin_int.value * 2
      expect(rec.generation).to eq 2

    end

    it "should #put, #add float" do

      rec = client.operate(key, [
                             Aerospike::Operation.put(bin_float),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_float.name]).to eq bin_float.value
      expect(rec.generation).to eq 1

      rec = client.operate(key, [
                             Aerospike::Operation.add(bin_float),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_str.name]).to be_within(0.00001).of(bin_float.value * 2)
      expect(rec.generation).to eq 2

    end

    it "should #put, #touch" do

      rec = client.operate(key, [
                             Aerospike::Operation.put(bin_int),
                             Aerospike::Operation.get,
      ])

      expect(rec.bins[bin_int.name]).to eq bin_int.value
      expect(rec.generation).to eq 1

      rec = client.operate(key, [
                             Aerospike::Operation.touch,
                             Aerospike::Operation.get_header,
      ])

      # expect(rec.bins).to be nil
      expect(rec.generation).to eq 2
    end

    context "with multiple read operations on same bin" do

      let(:map_bin) { Aerospike::Bin.new("map", { "a" => 3, "b" => 2, "c" => 1 }) }

      context "with record bin multiplicity SINGLE" do

        it "returns the result of the last operation" do
          client.put(key, [map_bin])

          return_type = Aerospike::CDT::MapReturnType::KEY_VALUE
          ops = [
            Aerospike::CDT::MapOperation.get_index(map_bin.name, 0, return_type: return_type),
            Aerospike::CDT::MapOperation.get_by_rank(map_bin.name, 0, return_type: return_type)
          ]
          policy = Aerospike::OperatePolicy.new(record_bin_multiplicity: Aerospike::RecordBinMultiplicity::SINGLE)
          result = client.operate(key, ops, policy)

          value = result.bins[map_bin.name]
          expect(value).to eq({ "c" => 1 })
        end

      end

      context "with record bin multiplicity ARRAY" do

        it "returns the results of all operations as an array" do
          client.put(key, [map_bin])

          return_type = Aerospike::CDT::MapReturnType::KEY_VALUE
          ops = [
            Aerospike::CDT::MapOperation.get_index(map_bin.name, 0, return_type: return_type),
            Aerospike::CDT::MapOperation.get_by_rank(map_bin.name, 0, return_type: return_type)
          ]
          policy = Aerospike::OperatePolicy.new(record_bin_multiplicity: Aerospike::RecordBinMultiplicity::ARRAY)
          result = client.operate(key, ops, policy)

          value = result.bins[map_bin.name]
          expect(value).to eq([ { "a" => 3 }, { "c" => 1 } ])
        end

      end

    end

  end

  context "Batch commands" do

    it "should successfully check existence of many keys" do

      KEY_CNT = 3000
      keys = Array.new(KEY_CNT)
      (0...KEY_CNT).to_a.each do |i|
        keys[i] = Support.gen_random_key
        client.put(keys[i], Aerospike::Bin.new('bin', 'value')) if i % 2 == 0
      end

      exists = client.batch_exists(keys)

      expect(exists.length).to eq KEY_CNT

      exists.each_with_index do |elem, i|
        expect(elem).to be (i % 2 == 0)
      end
    end

    it "should successfully check existence of keys" do

      key1 = Support.gen_random_key
      key2 = Support.gen_random_key
      key3 = Support.gen_random_key

      client.put(key1, Aerospike::Bin.new('bin', 'value'))
      client.put(key3, Aerospike::Bin.new('bin', 'value'))

      exists = client.batch_exists([key1, key2, key3])

      expect(exists.length).to eq 3

      expect(exists[0]).to eq(true)
      expect(exists[1]).to eq(false)
      expect(exists[2]).to eq(true)

    end

    it "should successfully get keys" do

      key1 = Support.gen_random_key
      key2 = Support.gen_random_key
      key3 = Support.gen_random_key

      bin = Aerospike::Bin.new('bin', 'value')
      client.put(key1, bin)
      client.put(key3, bin)

      records = client.batch_get([key1, key2, key3], ['bin'])

      expect(records.length).to eq 3

      expect(records[0].key).to eq key1
      expect(records[0].bins).to eq ({bin.name => bin.value})

      expect(records[1]).to be nil

      expect(records[2].key).to eq key3
      expect(records[2].bins).to eq ({bin.name => bin.value})

    end

    it "should successfully get headers for keys" do

      key1 = Support.gen_random_key
      key2 = Support.gen_random_key
      key3 = Support.gen_random_key

      bin = Aerospike::Bin.new('bin', 'value')
      client.put(key1, bin, ttl: 1000)
      client.put(key3, bin, ttl: 1000)

      records = client.batch_get_header([key1, key2, key3])

      expect(records.length).to eq 3

      expect(records[0].key).to eq key1
      expect(records[0].key.user_key).to eq key1.user_key
      expect(records[0].bins).to be nil
      expect(records[0].generation).to be 1
      expect(records[0].expiration).to be_within(10).of(1000)

      expect(records[1]).to be nil

      expect(records[2].key).to eq key3
      expect(records[2].key.user_key).to eq key3.user_key
      expect(records[2].bins).to be nil
      expect(records[2].generation).to be 1
      expect(records[2].expiration).to be_within(10).of(1000)

    end

  end

  describe "benchmarks", skip: true do

    it "benchmark #put #get" do
      bin = Aerospike::Bin.new('bin', 'value')
      key = Support.gen_random_key

      times = Benchmark.measure do
        1000.times do
          client.put(key, bin)
          client.get(key)
        end
      end
      puts times
    end

  end

end
