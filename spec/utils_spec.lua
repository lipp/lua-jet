local utils = require'jet.utils'

describe(
  'The jet.utils module',
  function()
    
    it('is_empty_table works',function()
        assert.is_true(utils.is_empty_table({}))
        assert.is_false(utils.is_empty_table({'asd'}))
        assert.is_false(utils.is_empty_table({a=123}))
      end)
    
    it('is_valid_path works',function()
        assert.is_true(utils.is_valid_path('abc'))
        assert.is_true(utils.is_valid_path('abc.123.PED'))
        assert.is_true(utils.is_valid_path('abc.123.PED#09821374'))
        assert.is_true(utils.is_valid_path('123abc&PPP#'))
        assert.is_true(utils.is_valid_path('p/t/erasd/;;;:'))
        assert.is_false(utils.is_valid_path('^asd'))
        assert.is_false(utils.is_valid_path('a^sd'))
        assert.is_false(utils.is_valid_path('$asd'))
        assert.is_false(utils.is_valid_path('asd$'))
        assert.is_false(utils.is_valid_path('asd*ppp'))
        assert.is_false(utils.is_valid_path('asdppp*'))
      end)
    
    it('remove works',function()
        local t = {2,5,6}
        local found = utils.remove(t,5)
        assert.is_true(found)
        assert.is_same({2,6},t)
        
        local t = {2,5,6}
        local found = utils.remove(t,4)
        assert.is_false(found)
        assert.is_same({2,5,6},t)
        
      end)
    
  end)

