local vm = require'jet.daemon.value_matcher'

describe(
  'The jet.daemon.value_matcher module',
  function()

    it('equals', function()
        local pred = vm.new({
            value = {
              equals = '123'
            }
        })
        assert.is_true(pred('123'))
        assert.is_falsy(pred(123))

        local pred = vm.new({
            value = {
              equals = 123
            }
        })
        assert.is_falsy(pred('123'))
        assert.is_true(pred(123))
      end)

    it('equals works with valueField', function()
        local pred = vm.new({
            valueField = {
              abc = {
                equals = '123'
              }
            }
        })
        assert.is_true(pred({abc = '123'}))
        assert.is_falsy(pred({abc = 123}))
        assert.is_falsy(pred(123))

        local pred = vm.new({
            valueField = {
              abc = {
                equals = 123
              }
            }
        })
        assert.is_falsy(pred({abc = '123'}))
        assert.is_true(pred({abc = 123}))
        assert.is_falsy(pred('123'))
      end)

    it('hasOneOf', function()
        local pred = vm.new({
            value = {
              hasOneOf = {123,'hello'}
            }
        })
        assert.is_true(pred({123,9820,333}))
        assert.is_true(pred({3,9820,123}))
        assert.is_true(pred({123}))
        assert.is_true(pred({1,2,3,4,5,5,6,'hello'}))
        assert.is_falsy(pred({920,122,999,'123'}))
        assert.is_falsy(pred(123))
      end)

    it('hasAllOf', function()
        local pred = vm.new({
            valueField = {
              tags = {
                hasAllOf = {123,'hello'}
              }
            }
        })
        assert.is_falsy(pred({123,9820,333}))
        assert.is_true(pred({tags = {'hello',9820,123}}))
        assert.is_falsy(pred({tags = {'hello',9820,13}}))
        assert.is_falsy(pred({tags = {'helo',9820,123}}))
        assert.is_falsy(pred(123))
      end)

  end)
