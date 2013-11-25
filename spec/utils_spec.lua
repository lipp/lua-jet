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
        assert.is_true(utils.is_valid_path('123abc&PPP#'))
        assert.is_true(utils.is_valid_path('p/t/erasd/;;;:'))
        assert.is_false(utils.is_valid_path('^asd'))
        assert.is_false(utils.is_valid_path('a^sd'))
        assert.is_false(utils.is_valid_path('$asd'))
        assert.is_false(utils.is_valid_path('asd$'))
        assert.is_false(utils.is_valid_path('asd*ppp'))
        assert.is_false(utils.is_valid_path('asdppp*'))
      end)
    
  end)

