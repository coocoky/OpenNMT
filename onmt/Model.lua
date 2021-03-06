--[[ Generic Model class. ]]
local Model = torch.class('Model')

local options = {
  {
    '-model_type', 'seq2seq',
    [[Type of model to train. This option impacts all options choices.]],
    {
      enum = {'lm', 'seq2seq', 'seqtagger'},
      structural = 0
    }
  },
  {
    '-param_init', 0.1,
    [[Parameters are initialized over uniform distribution with support (-`param_init`, `param_init`).]],
    {
      valid = function(v) return v >= 0 and v <= 1 end,
      init_only = true
    }
  }
}

function Model.declareOpts(cmd)
  cmd:setCmdLineOptions(options, 'Model')
end

function Model:__init(args)
  self.args = onmt.utils.ExtendedCmdLine.getModuleOpts(args, options)
  self.models = {}
end

-- Dynamically change parameters in the graph.
function Model:changeParameters(changes)
  _G.logger:info('Applying new parameters:')

  for k, v in pairs(changes) do
    _G.logger:info(' * %s = ' .. v, k)

    for _, model in pairs(self.models) do
      model:apply(function(m)
        if k == 'dropout' and torch.typename(m) == 'nn.Dropout' then
          m:setp(v)
        elseif k:find('fix_word_vecs') and torch.typename(m) == 'onmt.WordEmbedding' then
          local enc = k == 'fix_word_vecs_enc' and torch.typename(model):find('Encoder')
          local dec = k == 'fix_word_vecs_dec' and torch.typename(model):find('Decoder')
          if enc or dec then
            m:fixEmbeddings(v == 1)
          end
        end
      end)
    end
  end

end

function Model:getInputLabelsCount(batch)
  return batch.sourceInput:ne(onmt.Constants.PAD):sum()
end

function Model:getOutputLabelsCount(batch)
  return self:getOutput(batch):ne(onmt.Constants.PAD):sum()
end

function Model:evaluate()
  for _, m in pairs(self.models) do
    m:evaluate()
  end
end

function Model:training()
  for _, m in pairs(self.models) do
    m:training()
  end
end

function Model:initParams()
  _G.logger:info('Initializing parameters...')

  local params, gradParams, orderedIndex = self:getParams()
  local numParams = 0

  for i, key in ipairs(orderedIndex) do
    params[i]:uniform(-self.args.param_init, self.args.param_init)

    self.models[key]:apply(function (m)
      if m.postParametersInitialization then
        m:postParametersInitialization()
      end
    end)

    numParams = numParams + params[i]:size(1)
  end

  _G.logger:info(' * number of parameters: ' .. numParams)

  return params, gradParams
end

function Model:getParams()
  -- Order the model table because we need all replicas to have the same order.
  local orderedIndex = {}
  for key in pairs(self.models) do
    table.insert(orderedIndex, key)
  end
  table.sort(orderedIndex)

  local params = {}
  local gradParams = {}

  for i, key in ipairs(orderedIndex) do
    params[i], gradParams[i] = self.models[key]:getParameters()
  end

  return params, gradParams, orderedIndex
end

return Model
