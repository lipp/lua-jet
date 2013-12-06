local pairs = pairs
local print = print
local next = next
local type = type

local new = function()
  local j = {}
  local radix_tree = {}
  local radix_elements = {}
  local return_tree = {}
  local lookup_fsm
  local root_lookup
  local leaf_lookup
  local radix_traverse
  local root_leaf_lookup
  local root_anypos_lookup
  
  
  lookup_fsm = function (wordpart, next_state, next_letter)
    if (wordpart:sub(next_state,next_state) ~= next_letter) then
      return false, 0
    end
    if (wordpart:len() == next_state) then
      return true, next_state
    else
      return false, next_state
    end
  end
  
  root_lookup = function( tree_instance, part, traverse, tree)
    if part:len() < 1 then
      if (traverse) then
        radix_traverse( tree_instance )
      else
        return_tree = tree_instance
      end
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])=="table" then
        root_lookup( tree_instance[s], part:sub(2), traverse)
      end
    end
  end
  
  leaf_lookup = function( tree_instance, word, state, only_end, traverse)
    local next_state = state+1
    for k, v in pairs(tree_instance) do
      if type(v)=="table" then
        local hit, next_state = lookup_fsm(word, next_state, k)
        if (hit == true) then
          if only_end then
            if type(v[next(v)])=="boolean" then
              radix_elements[next(v)] = true
            end
          else
            if traverse then
              radix_traverse( v )
            else
              table.insert(return_tree, v)
            end
          end
        else
          leaf_lookup( v, word, next_state, only_end, traverse);
        end
      end
    end
  end
  
  local add_to_tree
  add_to_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=true;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        tree_instance[s] = {};
      end
      add_to_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  local remove_from_tree
  remove_from_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=nil;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        return
      end
      remove_from_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  radix_traverse = function( tree_instance )
    for k, v in pairs(tree_instance) do
      if type(v)=="boolean" then
        radix_elements[k] = true
      elseif type(v)=="table" then
        radix_traverse( v );
      end
    end
  end
  
  local match_parts
  match_parts = function (tree_instance, parts)
    if (parts['equals']) then
      return_tree = {}
      root_lookup(tree_instance, parts['equals'], false)
      if type(return_tree[next(return_tree)])=="boolean" then
        radix_elements[next(return_tree)] = true
      end
    else
      local temp_tree = tree_instance
      if (parts['startsWith']) then
        return_tree = {}
        root_lookup(temp_tree, parts['startsWith'], false)
        temp_tree = return_tree
      end
      if (parts['contains']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['contains'], 0, false, false)
        temp_tree = return_tree
      end
      if (parts['endsWith']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['endsWith'], 0, true, false)
        temp_tree = return_tree
      end
      if temp_tree then
        radix_traverse(temp_tree)
      end
    end
  end
  
  local get_possible_matches
  get_possible_matches = function (peer, params, fetch_id, is_case_insensitive)
    local involves_path_match = params.path
    local involves_value_match = params.value or params.valueField
    local level = 'impossible'
    local radix_expressions = {}
    
    if involves_path_match and not is_case_insensitive then
      for name,value in pairs(params.path) do
        if name == 'equals' or name == 'startsWith' or name == 'endsWith' or name == 'contains' then
          if radix_expressions[name] then
            level = 'impossible'
            break
          end
          radix_expressions[name] = value
          if level == 'partial_pending' or involves_value_match then
            level = 'partial'
          elseif level ~= 'partial' then
            level = 'all'
          end
        else
          if level == 'easy' or level == 'partial' then
            level = 'partial'
          else
            level = 'partial_pending'
          end
        end
      end
      if level == 'partial_pending' then
        level = 'impossible'
      end
    end       
    
    if level ~= 'impossible' then
      radix_elements = {}
      match_parts(radix_tree, radix_expressions)
      return radix_elements
    else
	  return nil
    end
  end
  
  j.add = function (word)
    add_to_tree(radix_tree, word)
  end
  j.remove = function (word)
    remove_from_tree(radix_tree, word)
  end
  j.get_possible_matches = get_possible_matches
  
  return j
end

return {
  new = new
}
