defmodule Pipeline.PrestoTest do
  use ExUnit.Case
  use Placebo
  import Checkov

  alias Pipeline.Presto

  describe "create/1" do
    @tag capture_log: true
    test "converts schema type value to proper presto type" do
      schema = [
        %{name: "first_name", type: "string"},
        %{name: "height", type: "long"},
        %{name: "weight", type: "float"},
        %{name: "identifier", type: "decimal"},
        %{name: "payload", type: "json"}
      ]

      expected =
        ~s|CREATE TABLE IF NOT EXISTS table_name ("first_name" varchar, "height" bigint, "weight" double, "identifier" decimal, "payload" varchar)|

      assert {:ok, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    @tag capture_log: true
    test "handles row" do
      schema = [
        %{
          name: "spouse",
          type: "map",
          subSchema: [
            %{name: "first_name", type: "string"},
            %{
              name: "next_of_kin",
              type: "map",
              subSchema: [
                %{name: "first_name", type: "string"},
                %{name: "date_of_birth", type: "date"}
              ]
            }
          ]
        }
      ]

      expected =
        ~s|CREATE TABLE IF NOT EXISTS table_name ("spouse" row("first_name" varchar, "next_of_kin" row("first_name" varchar, "date_of_birth" date)))|

      assert {:ok, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    @tag capture_log: true
    test "handles array" do
      schema = [
        %{name: "friend_names", type: "list", itemType: "string"}
      ]

      expected = ~s|CREATE TABLE IF NOT EXISTS table_name ("friend_names" array(varchar))|
      assert {:ok, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    @tag capture_log: true
    test "handles array of maps" do
      schema = [
        %{
          name: "friend_groups",
          type: "list",
          itemType: "map",
          subSchema: [
            %{name: "first_name", type: "string"},
            %{name: "last_name", type: "string"}
          ]
        }
      ]

      expected =
        ~s|CREATE TABLE IF NOT EXISTS table_name ("friend_groups" array(row("first_name" varchar, "last_name" varchar)))|

      assert {:ok, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    @tag capture_log: true
    test "returns error tuple with type message when field cannot be mapped" do
      schema = [%{name: "my_field", type: "unsupported"}]
      expected = "unsupported Type is not supported"
      assert {:error, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    @tag capture_log: true
    test "returns error tuple when given invalid schema" do
      schema = [%{name: "my_field"}]
      expected =
        "Unable to parse schema: %Pipeline.Presto.InvalidSchemaError{message: \"Invalid Schema: field %{name: \\\"my_field\\\"}\"}"

      assert {:error, ^expected} = Presto.create(%{table: "table_name", schema: schema})
    end

    test "accepts a select statement to create table from" do
      expected = "create table one__two as (select * from three__four)"
      assert {:ok, ^expected} = Presto.create(%{table: "one__two", as: "select * from three__four"})
    end
  end

  describe "insert/2" do
    test "build generates a valid statement when given a schema and data" do
      data = [
        %{"id" => 1, "name" => "Fred"},
        %{"id" => 2, "name" => "Gred"},
        %{"id" => 3, "name" => "Hred"}
      ]

      result = Presto.insert(config(), data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(1,'Fred'),row(2,'Gred'),row(3,'Hred')/
      assert result == expected_result
    end

    test "build generates a valid statement when given a schema and data that are not in the same order" do
      schema = config()

      data = [
        %{"name" => "Iom", "id" => 9},
        %{"name" => "Jom", "id" => 8},
        %{"name" => "Yom", "id" => 7}
      ]

      result = Presto.insert(schema, data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(9,'Iom'),row(8,'Jom'),row(7,'Yom')/

      assert result == expected_result
    end

    test "escapes single quotes correctly" do
      data = [
        %{"id" => 9, "name" => "Nathaniel's test"}
      ]

      result = Presto.insert(config(), data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(9,'Nathaniel''s test')/

      assert result == expected_result
    end

    test "inserts null when field is null" do
      data = [
        %{"id" => 9, "name" => nil}
      ]

      result = Presto.insert(config(), data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(9,null)/

      assert result == expected_result
    end

    test "inserts null when timestamp field is an empty string" do
      dataset = config([%{name: "id", type: "integer"}, %{name: "date", type: "timestamp"}])
      data = [%{"id" => 9, "date" => ""}]

      result = Presto.insert(dataset, data)
      expected_result = ~s/insert into "rivers" ("id","date") values row(9,null)/

      assert result == expected_result
    end

    test "inserts a presto-appropriate date when inserting a date" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_date", type: "date"}])
      data = [%{"id" => 9, "start_date" => "1900-01-01T00:00:00"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s/insert into "rivers" ("id","start_date") values row(9,date(date_parse('1900-01-01T00:00:00', '%Y-%m-%dT%H:%i:%S')))/

      assert result == expected_result
    end

    test "inserts 1 when integer field is a signed 1" do
      data = [
        %{"id" => "+1", "name" => "Hroki"},
        %{"id" => "-1", "name" => "Doki"}
      ]

      result = Presto.insert(config(), data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(1,'Hroki'),row(-1,'Doki')/

      assert result == expected_result
    end

    test "inserts number when float field is a signed number" do
      dataset = config([%{name: "id", type: "integer"}, %{name: "floater", type: "float"}])
      data = [%{"id" => "1", "floater" => "+4.5"}, %{"id" => "1", "floater" => "-4.5"}]

      result = Presto.insert(dataset, data)
      expected_result = ~s/insert into "rivers" ("id","floater") values row(1,4.5),row(1,-4.5)/

      assert result == expected_result
    end

    test "inserts without timezone when inserting a timestamp" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_time", type: "timestamp"}])
      data = [%{"id" => 9, "start_time" => "2019-04-17T14:23:09.030939"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s/insert into "rivers" ("id","start_time") values row(9,date_parse('2019-04-17T14:23:09.030939', '%Y-%m-%dT%H:%i:%S.%f'))/

      assert result == expected_result
    end

    test "inserts using proper format when inserting a timestamp" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_time", type: "timestamp"}])
      data = [%{"id" => 9, "start_time" => "2019-06-02T16:30:17"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s/insert into "rivers" ("id","start_time") values row(9,date_parse('2019-06-02T16:30:17', '%Y-%m-%dT%H:%i:%S'))/

      assert result == expected_result
    end

    test "inserts using proper format when inserting a timestamp that ends in Z" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_time", type: "timestamp"}])
      data = [%{"id" => 9, "start_time" => "2019-06-11T18:34:33.484840Z"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s/insert into "rivers" ("id","start_time") values row(9,date_parse('2019-06-11T18:34:33.484840Z', '%Y-%m-%dT%H:%i:%S.%fZ'))/

      assert result == expected_result
    end

    test "inserts using proper format when inserting a timestamp that ends in Z without milliseconds" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_time", type: "timestamp"}])
      data = [%{"id" => 9, "start_time" => "2019-06-14T18:16:32Z"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s/insert into "rivers" ("id","start_time") values row(9,date_parse('2019-06-14T18:16:32Z', '%Y-%m-%dT%H:%i:%SZ'))/

      assert result == expected_result
    end

    test "inserts time data types as strings" do
      dataset = config([%{name: "id", type: "number"}, %{name: "start_time", type: "time"}])
      data = [%{"id" => 9, "start_time" => "23:00:13.001"}]

      result = Presto.insert(dataset, data)
      expected_result = ~s/insert into "rivers" ("id","start_time") values row(9,'23:00:13.001')/

      assert result == expected_result
    end

    test "handles empty string values with a type of string" do
      data = [
        %{"id" => 1, "name" => "Fred"},
        %{"id" => 2, "name" => "Gred"},
        %{"id" => 3, "name" => ""}
      ]

      result = Presto.insert(config(), data)
      expected_result = ~s/insert into "rivers" ("id","name") values row(1,'Fred'),row(2,'Gred'),row(3,'')/

      assert result == expected_result
    end

    test "treats json string as varchar" do
      data = [
        %{
          "id" => 1,
          "name" => "Fred",
          "payload" => "{\"parent\":{\"children\":[[-35.123,123.456]],\"id\":\"daID\"}}"
        }
      ]

      result = Presto.insert(get_json_schema(), data)

      expected_result =
        ~s/insert into "rivers" ("id","name","payload") values row(1,'Fred','{\"parent\":{\"children\":[[-35.123,123.456]],\"id\":\"daID\"}}')/

      assert result == expected_result
    end

    test "escapes quotes in json" do
      data = [
        %{
          "id" => 1,
          "name" => "Fred",
          "payload" => "{\"parent\":{\"children\":[[-35.123,123.456]],\"id\":\"daID\", \"name\": \"Chiggin's\"}}"
        }
      ]

      result = Presto.insert(get_json_schema(), data)

      expected_result =
        ~s|insert into "rivers" ("id","name","payload") values row(1,'Fred','{\"parent\":{\"children\":[[-35.123,123.456]],\"id\":\"daID\", \"name\": \"Chiggin''s\"}}')|

      assert result == expected_result
    end

    test "treats empty string as varchar" do
      data = [%{"id" => 1, "name" => "Fred", "payload" => ""}]

      result = Presto.insert(get_json_schema(), data)
      expected_result = ~s/insert into "rivers" ("id","name","payload") values row(1,'Fred','')/

      assert result == expected_result
    end

    test "build generates a valid statement when given a complex nested schema and complex nested data" do
      nested_data = get_complex_nested_data()
      result = Presto.insert(get_complex_nested_schema(), nested_data)

      expected_result =
        ~s|insert into "rivers" ("first_name","age","friend_names","friends","spouse") values row('Joe',10,array['bob','sally'],array[row('Bill','Bunco'),row('Sally','Bosco')],row('Susan','female',row('Joel','12/07/1941')))|

      assert result == expected_result
    end

    test "build generates a valid statement when given a map" do
      schema = [
        %{
          name: "first_name",
          type: "string"
        },
        %{
          name: "spouse",
          type: "map",
          subSchema: [%{name: "first_name", type: "string"}]
        }
      ]

      dataset = config(schema)

      data = [
        %{"first_name" => "Bob", "spouse" => %{"first_name" => "Hred"}},
        %{"first_name" => "Rob", "spouse" => %{"first_name" => "Freda"}}
      ]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s|insert into "rivers" ("first_name","spouse") values row('Bob',row('Hred')),row('Rob',row('Freda'))|

      assert result == expected_result
    end

    test "build generates a valid statement when given nested rows" do
      schema = [
        %{
          name: "spouse",
          type: "map",
          subSchema: [
            %{name: "first_name", type: "string"},
            %{
              name: "next_of_kin",
              type: "map",
              subSchema: [
                %{name: "first_name", type: "string"},
                %{name: "date_of_birth", type: "string"}
              ]
            }
          ]
        }
      ]

      dataset = config(schema)

      data = [
        %{
          "spouse" => %{
            "first_name" => "Georgia",
            "next_of_kin" => %{
              "first_name" => "Bimmy",
              "date_of_birth" => "01/01/1900"
            }
          }
        },
        %{
          "spouse" => %{
            "first_name" => "Regina",
            "next_of_kin" => %{
              "first_name" => "Jammy",
              "date_of_birth" => "01/01/1901"
            }
          }
        }
      ]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s|insert into "rivers" ("spouse") values row(row('Georgia',row('Bimmy','01/01/1900'))),row(row('Regina',row('Jammy','01/01/1901')))|

      assert result == expected_result
    end

    test "build generates a valid statement when given an array" do
      dataset = config([%{name: "friend_names", type: "list", itemType: "string"}])
      data = [%{"friend_names" => ["Sam", "Jonesy"]}, %{"friend_names" => []}]

      result = Presto.insert(dataset, data)
      expected_result = ~s|insert into "rivers" ("friend_names") values row(array['Sam','Jonesy']),row(array[])|

      assert result == expected_result
    end

    test "build generates a valid statement when given a date" do
      dataset = config([%{name: "date_of_birth", type: "date"}])
      data = [%{"date_of_birth" => "1901-01-01T00:00:00"}, %{"date_of_birth" => "1901-01-21T00:00:00"}]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s|insert into "rivers" ("date_of_birth") values row(date(date_parse('1901-01-01T00:00:00', '%Y-%m-%dT%H:%i:%S'))),row(date(date_parse('1901-01-21T00:00:00', '%Y-%m-%dT%H:%i:%S')))|

      assert result == expected_result
    end

    test "build generates a valid statement when given an array of maps" do
      schema = [
        %{
          name: "friend_groups",
          type: "list",
          itemType: "map",
          subSchema: [
            %{name: "first_name", type: "string"},
            %{name: "last_name", type: "string"}
          ]
        }
      ]

      dataset = config(schema)

      data = [
        %{
          "friend_groups" => [
            %{"first_name" => "Hayley", "last_name" => "Person"},
            %{"first_name" => "Jason", "last_name" => "Doe"}
          ]
        },
        %{
          "friend_groups" => [
            %{"first_name" => "Saint-John", "last_name" => "Johnson"}
          ]
        }
      ]

      result = Presto.insert(dataset, data)

      expected_result =
        ~s|insert into "rivers" ("friend_groups") values row(array[row('Hayley','Person'),row('Jason','Doe')]),row(array[row('Saint-John','Johnson')])|

      assert result == expected_result
    end
  end

  describe "drop/1" do
    test "generates a valid DROP TABLE statement" do
      expected = "drop table if exists foo__bar"
      assert ^expected = Presto.drop(%{table: "foo__bar"})
    end
  end

  describe "alter/1" do
    test "generates a valid ALTER TABLE statement" do
      expected = "alter table foo__bar rename to foo__baz"
      assert ^expected = Presto.alter(%{table: "foo__bar", alteration: "rename to foo__baz"})
    end
  end

  describe "convert_type/1" do
    data_test "convert simple type #{type} to #{result}" do
      assert %{column_name: "name", data_type: result} == Presto.convert_type(%{name: "name", type: type})

      where([
        [:type, :result],
        ["string", "varchar"],
        ["boolean", "boolean"],
        ["date", "date"],
        ["double", "double"],
        ["float", "double"],
        ["integer", "integer"],
        ["long", "bigint"],
        ["json", "varchar"],
        ["timestamp", "timestamp"],
        ["decimal(18,3)", "decimal(18,3)"]
      ])
    end

    data_test "converts list of #{type} to array(#{type})" do
      assert %{column_name: "name", data_type: "array(#{result})"} ==
               Presto.convert_type(%{name: "name", type: "list", itemType: type})

      where([
        [:type, :result],
        ["string", "varchar"],
        ["boolean", "boolean"],
        ["date", "date"],
        ["double", "double"],
        ["float", "double"],
        ["integer", "integer"],
        ["long", "bigint"],
        ["json", "varchar"],
        ["timestamp", "timestamp"]
      ])
    end

    test "converts map to row type" do
      field = %{
        name: "map",
        type: "map",
        subSchema: [
          %{name: "name", type: "string"},
          %{name: "age", type: "integer"}
        ]
      }

      assert %{column_name: "map", data_type: ~s|row("name" varchar, "age" integer)|} == Presto.convert_type(field)
    end

    test "converts to list of map to array(row)" do
      field = %{
        name: "list_of_maps",
        type: "list",
        itemType: "map",
        subSchema: [
          %{name: "name", type: "string"},
          %{name: "age", type: "integer"}
        ]
      }

      assert %{column_name: "list_of_maps", data_type: ~s|array(row("name" varchar, "age" integer))|} ==
               Presto.convert_type(field)
    end

    test "raises exception when unable to convert field" do
      assert_raise Presto.FieldTypeError, "invalid Type is not supported", fn ->
        Presto.convert_type(%{name: "invalid", type: "invalid"})
      end
    end
  end

  defp config(schema \\ [%{name: "id", type: "integer"}, %{name: "name", type: "string"}]) do
    %{table: "rivers", schema: schema}
  end

  defp get_json_schema() do
    config([
      %{name: "id", type: "integer"},
      %{name: "name", type: "string"},
      %{name: "payload", type: "json"}
    ])
  end

  defp get_complex_nested_schema() do
    schema = [
      %{name: "first_name", type: "string"},
      %{name: "age", type: "integer"},
      %{name: "friend_names", type: "list", itemType: "string"},
      %{
        name: "friends",
        type: "list",
        itemType: "map",
        subSchema: [
          %{name: "first_name", type: "string"},
          %{name: "pet", type: "string"}
        ]
      },
      %{
        name: "spouse",
        type: "map",
        subSchema: [
          %{name: "first_name", type: "string"},
          %{name: "gender", type: "string"},
          %{
            name: "next_of_kin",
            type: "map",
            subSchema: [
              %{name: "first_name", type: "string"},
              %{name: "date_of_birth", type: "string"}
            ]
          }
        ]
      }
    ]

    config(schema)
  end

  defp get_complex_nested_data() do
    [
      %{
        "first_name" => "Joe",
        "age" => 10,
        "friend_names" => ["bob", "sally"],
        "friends" => [
          %{"first_name" => "Bill", "pet" => "Bunco"},
          %{"first_name" => "Sally", "pet" => "Bosco"}
        ],
        "spouse" => %{
          "first_name" => "Susan",
          "gender" => "female",
          "next_of_kin" => %{
            "first_name" => "Joel",
            "date_of_birth" => "12/07/1941"
          }
        }
      }
    ]
  end
end
