--
--  Copyright (c) 2014, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
testLogger = optim.Logger(paths.concat(opt.save, 'test.log'))

local batchNumber
local top1_center, loss
local timer = torch.Timer()
local c = require 'trepl.colorize'

function test()
   mp.info(c.blue"==>".. " validation test epoch # " .. c.blue(''..epoch),8)
   if epoch>1 then mp.erase(10) end
   
   batchNumber = 0
   cutorch.synchronize()
   timer:reset()

   -- set the dropouts to evaluate mode
   model:evaluate()

   top1_center = 0
   loss = 0
   for i = 1, math.ceil(nTest/opt.batchSize) do -- nTest is set in 1_data.lua
      local indexStart = (i-1) * opt.batchSize + 1
      local indexEnd = math.min(nTest, indexStart + opt.batchSize - 1)
      donkeys:addjob(
         -- work to be done by donkey thread
         function()
            local inputs, labels = testLoader:get(indexStart, indexEnd)
            return inputs, labels
         end,
         -- callback that is run in the main thread once the work is done
         testBatch
      )
   end

   donkeys:synchronize()
   cutorch.synchronize()

   top1_center = top1_center * 100 / nTest
   loss = loss / nTest -- because loss is calculated per batch
   testLogger:add{
      ['% top1 accuracy (test set) (center crop)'] = top1_center,
      ['avg loss (test set)'] = loss
   }
   
   mp.progress(nTest,nTest,9)
   mp.erase(10)
   mp.info(string.format('Epoch: [%d][TESTING SUMMARY] Total Time(s): %.2f \t'
                          .. 'average loss (per batch): %.2f \t '
                          .. 'accuracy [Center](%%):\t top-1 %.2f\t ',
                       epoch, timer:time().real, loss, top1_center),10)


end -- of test()
-----------------------------------------------------------------------------
local inputs = torch.CudaTensor()
local labels = torch.CudaTensor()
local inferenceTimer = torch.Timer()
local dataTimer = torch.Timer()

function testBatch(inputsCPU, labelsCPU)
   inferenceTimer:reset()
   local dataLoadingTime = dataTimer:time().real
   
   batchNumber = batchNumber + opt.batchSize

   inputs:resize(inputsCPU:size()):copy(inputsCPU)
   labels:resize(labelsCPU:size()):copy(labelsCPU)

   local outputs = model:forward(inputs)
   local err = criterion:forward(outputs, labels)
   cutorch.synchronize()
   local pred = outputs:float()

   loss = loss + err * outputs:size(1)

   local _, pred_sorted = pred:sort(2, true)
   for i=1,pred:size(1) do
      local g = labelsCPU[i]
      if pred_sorted[i][1] == g then top1_center = top1_center + 1 end
   end
   
   mp.progress(batchNumber,nTest,9)
   mp.info((' Time %.3f Err %.4f Top1-%%: %.2f DataLoadingTime %.3f'):format(
          inferenceTimer:time().real, err, top1_center,dataLoadingTime),10)
          
   dataTimer:reset()
end
