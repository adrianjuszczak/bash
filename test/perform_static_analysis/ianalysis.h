#ifndef ANALYSIS_H
#define ANALYSIS_H

#include <string>

class IAnalysis
{
    public:
    virtual ~IAnalysis() = default;
    virtual void log(const std::string &ctxId, const std::string &msg) = 0;
};


#endif