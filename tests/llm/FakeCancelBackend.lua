require("love.timer")

local FakeCancelBackend = {}

function FakeCancelBackend.run(job, emit)
    emit("working")
    while not (job.isCanceled and job.isCanceled()) do
        love.timer.sleep(0.005)
    end
    error("request canceled")
end

return FakeCancelBackend
